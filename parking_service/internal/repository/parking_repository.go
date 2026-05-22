package repository

import (
	"context"
	"errors"
	"log"
	"time"

	"github.com/jackc/pgconn"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"parking-service/internal/model"
	"parking-service/internal/service"
)

type ParkingRepository struct {
	db *pgxpool.Pool
}

func NewParkingRepository(db *pgxpool.Pool) *ParkingRepository {
	return &ParkingRepository{db: db}
}

func (r *ParkingRepository) StartParking(
	userID *int,
	spotID int,
	start time.Time,
	duration time.Duration,
	source string,
) error {
	log.Println("START PARKING CALLED:", userID, spotID)

	if userID == nil {
		// симуляция — только обновляем статус места, без сессии
		_, err := r.db.Exec(context.Background(),
			`UPDATE parking_spots SET status = 'OCCUPIED' WHERE id = $1`, spotID)
		return err
	}

	ctx := context.Background()
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var exists int
	err = tx.QueryRow(ctx, `
		SELECT 1 FROM parking_sessions
		WHERE user_id = $1 AND end_time IS NULL LIMIT 1
	`, *userID).Scan(&exists)

	if err == nil {
		return service.ErrUserHasActiveParking
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}

	var status string
	err = tx.QueryRow(ctx,
		`SELECT status FROM parking_spots WHERE id = $1 FOR UPDATE`,
		spotID,
	).Scan(&status)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return service.ErrSpotNotFound
		}
		return err
	}
	if status == "OCCUPIED" {
		return service.ErrSpotOccupied
	}

	_, err = tx.Exec(ctx,
		`UPDATE parking_spots SET status = 'OCCUPIED' WHERE id = $1`, spotID)
	if err != nil {
		return err
	}

	expiresAt := start.Add(duration)
	log.Println("INSERT SESSION:", *userID, spotID, "expires_at", expiresAt)
	_, err = tx.Exec(ctx,
		`INSERT INTO parking_sessions (user_id, spot_id, start_time, expires_at, source)
		 VALUES ($1, $2, $3, $4, $5)`,
		*userID, spotID, start, expiresAt, source,
	)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return service.ErrUserHasActiveParking
		}
		return err
	}

	log.Println("SESSION CREATED SUCCESSFULLY")
	return tx.Commit(ctx)
}

func (r *ParkingRepository) EndParking(spotID int, end time.Time) error {
	ctx := context.Background()
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var userID *int
	var startTime time.Time
	var source string

	err = tx.QueryRow(ctx,
		`SELECT user_id, start_time, COALESCE(source, 'SYSTEM')
		 FROM parking_sessions
		 WHERE spot_id = $1 AND end_time IS NULL`,
		spotID,
	).Scan(&userID, &startTime, &source)

	hasSession := err == nil
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}

	// Сессия найдена — переносим в историю и удаляем.
	if hasSession {
		_, err = tx.Exec(ctx,
			`INSERT INTO parking_history (user_id, spot_id, start_time, end_time, source)
			 VALUES ($1, $2, $3, $4, $5)`,
			userID, spotID, startTime, end, source,
		)
		if err != nil {
			return err
		}

		_, err = tx.Exec(ctx,
			`DELETE FROM parking_sessions WHERE spot_id = $1 AND end_time IS NULL`, spotID)
		if err != nil {
			return err
		}
	}

	// Статус места всегда переводим в FREE, даже если сессии не было
	// (симуляция меняет статус без записи в parking_sessions).
	_, err = tx.Exec(ctx,
		`UPDATE parking_spots SET status = 'FREE' WHERE id = $1`, spotID)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (r *ParkingRepository) GetAllSpotIDs() ([]int, error) {
	rows, err := r.db.Query(context.Background(), `SELECT id FROM parking_spots`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, nil
}

func (r *ParkingRepository) GetAllSpots() ([]model.SpotDTO, error) {
	rows, err := r.db.Query(context.Background(),
		`SELECT id, zone_id, spot_number, status
		 FROM parking_spots ORDER BY zone_id, spot_number`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var spots []model.SpotDTO
	for rows.Next() {
		var s model.SpotDTO
		if err := rows.Scan(&s.ID, &s.ZoneID, &s.SpotNumber, &s.Status); err != nil {
			return nil, err
		}
		spots = append(spots, s)
	}
	return spots, nil
}

func (r *ParkingRepository) GetActiveParking(userID int) (int, time.Time, time.Time, error) {
	var spotID int
	var start time.Time
	var expires *time.Time
	err := r.db.QueryRow(context.Background(),
		`SELECT spot_id, start_time, expires_at FROM parking_sessions
		 WHERE user_id = $1 AND end_time IS NULL`, userID,
	).Scan(&spotID, &start, &expires)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, time.Time{}, time.Time{}, service.ErrNoActiveParking
	}
	if err != nil {
		return 0, time.Time{}, time.Time{}, err
	}
	var exp time.Time
	if expires != nil {
		exp = *expires
	}
	return spotID, start, exp, nil
}

// ExtendUserParking продлевает активную сессию пользователя:
// expires_at += additional. Если суммарная длительность (от start_time
// до нового expires_at) превышает maxTotal, возвращает ErrExtensionTooLong.
// Возвращает обновлённый expires_at для ответа клиенту.
func (r *ParkingRepository) ExtendUserParking(
	userID int,
	additional time.Duration,
	maxTotal time.Duration,
) (time.Time, error) {
	ctx := context.Background()
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return time.Time{}, err
	}
	defer tx.Rollback(ctx)

	var spotID int
	var startTime time.Time
	var currentExpires *time.Time
	err = tx.QueryRow(ctx,
		`SELECT spot_id, start_time, expires_at
		 FROM parking_sessions
		 WHERE user_id = $1 AND end_time IS NULL
		 FOR UPDATE`, userID,
	).Scan(&spotID, &startTime, &currentExpires)
	if errors.Is(err, pgx.ErrNoRows) {
		return time.Time{}, service.ErrNoActiveParking
	}
	if err != nil {
		return time.Time{}, err
	}

	// База от которой считаем продление: текущий expires_at,
	// или (если он отсутствует) start_time + дефолт.
	var baseExpires time.Time
	if currentExpires != nil {
		baseExpires = *currentExpires
	} else {
		baseExpires = startTime
	}
	newExpires := baseExpires.Add(additional)

	// Защита: не разрешаем продлить дольше maxTotal от старта.
	if newExpires.Sub(startTime) > maxTotal {
		return time.Time{}, service.ErrExtensionTooLong
	}

	_, err = tx.Exec(ctx,
		`UPDATE parking_sessions
		 SET expires_at = $1
		 WHERE user_id = $2 AND end_time IS NULL`,
		newExpires, userID)
	if err != nil {
		return time.Time{}, err
	}

	if err := tx.Commit(ctx); err != nil {
		return time.Time{}, err
	}
	return newExpires, nil
}

// HasActiveUserSession отвечает «true», если на месте есть активная
// (end_time IS NULL) сессия с непустым user_id. Используется, чтобы
// симуляция не сносила пользовательскую бронь.
func (r *ParkingRepository) HasActiveUserSession(spotID int) (bool, error) {
	var exists bool
	err := r.db.QueryRow(context.Background(),
		`SELECT EXISTS(
			SELECT 1 FROM parking_sessions
			WHERE spot_id = $1 AND end_time IS NULL AND user_id IS NOT NULL
		)`, spotID).Scan(&exists)
	return exists, err
}

// ResetDemoState освобождает все «висячие» состояния парковки. Удаляет
// все активные сессии (с переносом в историю как INTERRUPTED) и
// возвращает каждое место в FREE. Используется при старте сервера
// в демо-режиме, чтобы перезапуск всегда начинался с чистой картинки.
func (r *ParkingRepository) ResetDemoState() error {
	ctx := context.Background()
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// Активные пользовательские сессии перенесём в историю.
	_, err = tx.Exec(ctx,
		`INSERT INTO parking_history (user_id, spot_id, start_time, end_time, source)
		 SELECT user_id, spot_id, start_time, NOW(), 'INTERRUPTED'
		 FROM parking_sessions
		 WHERE end_time IS NULL AND user_id IS NOT NULL`)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `DELETE FROM parking_sessions WHERE end_time IS NULL`)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `UPDATE parking_spots SET status = 'FREE' WHERE status <> 'FREE'`)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// ExpireDueSessions ends all sessions whose expires_at has passed,
// transactionally moving them to history and freeing the corresponding
// spots. Returns the list of expired spot IDs so the caller can broadcast
// WS updates.
func (r *ParkingRepository) ExpireDueSessions(now time.Time) ([]int, error) {
	ctx := context.Background()
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	rows, err := tx.Query(ctx,
		`SELECT id, user_id, spot_id, start_time, COALESCE(source, 'SYSTEM')
		 FROM parking_sessions
		 WHERE end_time IS NULL AND expires_at IS NOT NULL AND expires_at <= $1`, now)
	if err != nil {
		return nil, err
	}

	type expiredSession struct {
		id      int
		userID  int
		spotID  int
		start   time.Time
		source  string
	}
	var sessions []expiredSession
	for rows.Next() {
		var s expiredSession
		if err := rows.Scan(&s.id, &s.userID, &s.spotID, &s.start, &s.source); err != nil {
			rows.Close()
			return nil, err
		}
		sessions = append(sessions, s)
	}
	rows.Close()

	if len(sessions) == 0 {
		return nil, tx.Commit(ctx)
	}

	spotIDs := make([]int, 0, len(sessions))
	for _, s := range sessions {
		_, err = tx.Exec(ctx,
			`INSERT INTO parking_history (user_id, spot_id, start_time, end_time, source)
			 VALUES ($1, $2, $3, $4, $5)`,
			s.userID, s.spotID, s.start, now, "EXPIRED",
		)
		if err != nil {
			return nil, err
		}
		_, err = tx.Exec(ctx, `DELETE FROM parking_sessions WHERE id = $1`, s.id)
		if err != nil {
			return nil, err
		}
		_, err = tx.Exec(ctx, `UPDATE parking_spots SET status = 'FREE' WHERE id = $1`, s.spotID)
		if err != nil {
			return nil, err
		}
		spotIDs = append(spotIDs, s.spotID)
	}

	return spotIDs, tx.Commit(ctx)
}

func (r *ParkingRepository) GetStats() (int, int, int, error) {
	var total, occupied, free int
	err := r.db.QueryRow(context.Background(),
		`SELECT
		  COUNT(*),
		  COUNT(*) FILTER (WHERE status = 'OCCUPIED'),
		  COUNT(*) FILTER (WHERE status = 'FREE')
		 FROM parking_spots`,
	).Scan(&total, &occupied, &free)
	if err != nil {
		return 0, 0, 0, err
	}
	return total, occupied, free, nil
}

func (r *ParkingRepository) GetSpotsByZone(zoneID int) ([]model.SpotDTO, error) {
	rows, err := r.db.Query(context.Background(),
		`SELECT id, zone_id, spot_number, status
		 FROM parking_spots WHERE zone_id = $1 ORDER BY spot_number`, zoneID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var spots []model.SpotDTO
	for rows.Next() {
		var s model.SpotDTO
		if err := rows.Scan(&s.ID, &s.ZoneID, &s.SpotNumber, &s.Status); err != nil {
			return nil, err
		}
		spots = append(spots, s)
	}
	return spots, nil
}

func (r *ParkingRepository) GetUserHistory(userID int) ([]map[string]interface{}, error) {
	rows, err := r.db.Query(context.Background(),
		`SELECT spot_id, start_time, end_time FROM parking_history
		 WHERE user_id = $1 ORDER BY start_time DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	history := []map[string]interface{}{}
	for rows.Next() {
		var spotID int
		var start time.Time
		var end *time.Time
		if err := rows.Scan(&spotID, &start, &end); err != nil {
			return nil, err
		}
		history = append(history, map[string]interface{}{
			"spot_id":    spotID,
			"start_time": start,
			"end_time":   end,
		})
	}
	return history, nil
}

func (r *ParkingRepository) GetParkingMap() ([]model.ZoneWithSpots, error) {
	rows, err := r.db.Query(context.Background(),
		`SELECT z.id, z.name, s.id, s.zone_id, s.spot_number, s.status
		 FROM parking_zones z
		 LEFT JOIN parking_spots s ON s.zone_id = z.id
		 ORDER BY z.id, s.spot_number`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	zones := map[int]*model.ZoneWithSpots{}
	zoneOrder := []int{}

	for rows.Next() {
		var zoneID int
		var zoneName string
		var spot model.SpotDTO
		if err := rows.Scan(&zoneID, &zoneName, &spot.ID, &spot.ZoneID, &spot.SpotNumber, &spot.Status); err != nil {
			return nil, err
		}
		if _, ok := zones[zoneID]; !ok {
			zones[zoneID] = &model.ZoneWithSpots{ID: zoneID, Name: zoneName, Spots: []model.SpotDTO{}}
			zoneOrder = append(zoneOrder, zoneID)
		}
		zones[zoneID].Spots = append(zones[zoneID].Spots, spot)
	}

	result := make([]model.ZoneWithSpots, 0, len(zoneOrder))
	for _, id := range zoneOrder {
		result = append(result, *zones[id])
	}
	return result, nil
}

// ── ADMIN ──────────────────────────────────────────────────────────────

func (r *ParkingRepository) GetAllUsers() ([]map[string]interface{}, error) {
	rows, err := r.db.Query(context.Background(),
		`SELECT id, email, role, created_at FROM users ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	users := []map[string]interface{}{}
	for rows.Next() {
		var id int
		var email, role string
		var createdAt time.Time
		if err := rows.Scan(&id, &email, &role, &createdAt); err != nil {
			return nil, err
		}
		users = append(users, map[string]interface{}{
			"id": id, "email": email, "role": role, "created_at": createdAt,
		})
	}
	return users, nil
}

func (r *ParkingRepository) GetAllActiveSessions() ([]map[string]interface{}, error) {
	rows, err := r.db.Query(context.Background(),
		`SELECT ps.user_id, u.email, ps.spot_id, sp.spot_number, z.name, ps.start_time
		 FROM parking_sessions ps
		 JOIN users u         ON u.id  = ps.user_id
		 JOIN parking_spots sp ON sp.id = ps.spot_id
		 JOIN parking_zones z  ON z.id  = sp.zone_id
		 WHERE ps.end_time IS NULL
		 ORDER BY ps.start_time DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	sessions := []map[string]interface{}{}
	for rows.Next() {
		var userID, spotID, spotNumber int
		var email, zoneName string
		var startTime time.Time
		if err := rows.Scan(&userID, &email, &spotID, &spotNumber, &zoneName, &startTime); err != nil {
			return nil, err
		}
		sessions = append(sessions, map[string]interface{}{
			"user_id": userID, "email": email,
			"spot_id": spotID, "spot_number": spotNumber,
			"zone_name": zoneName, "start_time": startTime,
		})
	}
	return sessions, nil
}

func (r *ParkingRepository) GetAllParkingHistory() ([]map[string]interface{}, error) {
	rows, err := r.db.Query(context.Background(),
		`SELECT ph.user_id, u.email, ph.spot_id, sp.spot_number, z.name, ph.start_time, ph.end_time
		 FROM parking_history ph
		 JOIN users u         ON u.id  = ph.user_id
		 JOIN parking_spots sp ON sp.id = ph.spot_id
		 JOIN parking_zones z  ON z.id  = sp.zone_id
		 ORDER BY ph.start_time DESC LIMIT 200`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	history := []map[string]interface{}{}
	for rows.Next() {
		var userID, spotID, spotNumber int
		var email, zoneName string
		var startTime time.Time
		var endTime *time.Time
		if err := rows.Scan(&userID, &email, &spotID, &spotNumber, &zoneName, &startTime, &endTime); err != nil {
			return nil, err
		}
		history = append(history, map[string]interface{}{
			"user_id": userID, "email": email,
			"spot_id": spotID, "spot_number": spotNumber,
			"zone_name": zoneName, "start_time": startTime, "end_time": endTime,
		})
	}
	return history, nil
}

var _ service.ParkingRepository = (*ParkingRepository)(nil)
