package repository

import (
	"context"
	"errors"
	"parking-service/internal/model"
	"time"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"parking-service/internal/service"
	"log"
	"github.com/jackc/pgx/v5/pgconn"
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
	source string,
) error {

	log.Println("START PARKING CALLED:", userID, spotID)

	if userID == nil {
		return errors.New("userID is required")
	}

	ctx := context.Background()

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// 🔥 ПРОВЕРКА: уже есть активная парковка?
	var exists int
	err = tx.QueryRow(ctx, `
		SELECT 1
		FROM parking_sessions
		WHERE user_id = $1 AND end_time IS NULL
		LIMIT 1
	`, *userID).Scan(&exists)

	if err == nil {
		return errors.New("user already has active parking")
	}

	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}

	// 🔥 проверка места
	var status string
	err = tx.QueryRow(ctx,
		`SELECT status FROM parking_spots WHERE id = $1 FOR UPDATE`,
		spotID,
	).Scan(&status)

	
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return errors.New("spot not found")
		}
		return err
	}

	if status == "OCCUPIED" {
		return errors.New("spot already occupied")
	}

	// 🔥 обновляем место
	_, err = tx.Exec(ctx,
		`UPDATE parking_spots SET status = 'OCCUPIED' WHERE id = $1`,
		spotID,
	)
	if err != nil {
		return err
	}

	log.Println("INSERT SESSION:", *userID, spotID)

	// 🔥 вставка
	_, err = tx.Exec(ctx,
		`INSERT INTO parking_sessions (user_id, spot_id, start_time, source)
		 VALUES ($1, $2, $3, $4)`,
		*userID, spotID, start, source,
	)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) {
			if pgErr.Code == "23505" {
				return errors.New("user already has active parking")
			}
		}
		return err
	}
	log.Println("SESSION CREATED SUCCESSFULLY")
	return tx.Commit(ctx)
}

func (r *ParkingRepository) EndParking(
	spotID int,
	end time.Time,
) error {

	ctx := context.Background()
	tx, err := r.db.Begin(ctx)

	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var userID int
	var startTime time.Time

	err = tx.QueryRow(ctx,
		`SELECT user_id, start_time FROM parking_sessions
		 WHERE spot_id = $1`,
		spotID,
	).Scan(&userID, &startTime)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil // нет активной сессии — это нормально
		}
		return err
	}

	_, err = tx.Exec(ctx,
		`INSERT INTO parking_history (user_id, spot_id, start_time, end_time, source)
		 VALUES ($1, $2, $3, $4, 'SYSTEM')`,
		userID, spotID, startTime, end,
	)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx,
		`DELETE FROM parking_sessions WHERE spot_id = $1`,
		spotID,
	)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx,
		`UPDATE parking_spots SET status = 'FREE' WHERE id = $1`,
		spotID,
	)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (r *ParkingRepository) GetAllSpotIDs() ([]int, error) {
	rows, err := r.db.Query(context.Background(),
		`SELECT id FROM parking_spots`,
	)
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
		 FROM parking_spots
		 ORDER BY zone_id, spot_number`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var spots []model.SpotDTO
	for rows.Next() {
		var s model.SpotDTO
		if err := rows.Scan(
			&s.ID,
			&s.ZoneID,
			&s.SpotNumber,
			&s.Status,
		); err != nil {
			return nil, err
		}
		spots = append(spots, s)
	}

	return spots, nil
}

func (r *ParkingRepository) GetActiveParking(userID int) (int, time.Time, error) {

	row := r.db.QueryRow(
		context.Background(),
		`
		SELECT spot_id, start_time
		FROM parking_sessions
		WHERE user_id = $1 AND end_time IS NULL
		`,
		userID,
	)

	var spotID int
	var start time.Time

	err := row.Scan(&spotID, &start)

	if errors.Is(err, pgx.ErrNoRows) {
		return 0, time.Time{}, pgx.ErrNoRows
	}

	if err != nil {
		return 0, time.Time{}, err
	}

	return spotID, start, nil
}

func (r *ParkingRepository) GetStats() (int, int, int, error) {

	var total int
	var occupied int
	var free int

	err := r.db.QueryRow(context.Background(),
		`SELECT 
		 COUNT(*) as total,
		 COUNT(*) FILTER (WHERE status = 'OCCUPIED') as occupied,
		 COUNT(*) FILTER (WHERE status = 'FREE') as free
		 FROM parking_spots`,
	).Scan(&total, &occupied, &free)

	if err != nil {
		return 0, 0, 0, err
	}

	return total, occupied, free, nil
}

func (r *ParkingRepository) GetSpotsByZone(zoneID int) ([]model.SpotDTO, error) {

	rows, err := r.db.Query(context.Background(), `
		SELECT id, zone_id, spot_number, status
		FROM parking_spots
		WHERE zone_id = $1
		ORDER BY spot_number
	`, zoneID)

	if err != nil {
		return nil, err
	}
	defer rows.Close()

	spots := []model.SpotDTO{}

	for rows.Next() {

		var s model.SpotDTO

		err := rows.Scan(
			&s.ID,
			&s.ZoneID,
			&s.SpotNumber,
			&s.Status,
		)

		if err != nil {
			return nil, err
		}

		spots = append(spots, s)
	}

	return spots, nil
}
func (r *ParkingRepository) GetUserHistory(userID int) ([]map[string]interface{}, error) {

	rows, err := r.db.Query(context.Background(),
		`SELECT spot_id, start_time, end_time
		 FROM parking_history
		 WHERE user_id = $1
		 ORDER BY start_time DESC`,
		userID,
	)

	if err != nil {
		return nil, err
	}
	defer rows.Close()

	history := []map[string]interface{}{}

	for rows.Next() {
		var spotID int
		var start time.Time
		var end *time.Time

		err := rows.Scan(&spotID, &start, &end)
		if err != nil {
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

	rows, err := r.db.Query(context.Background(), `
		SELECT z.id, z.name, s.id, s.zone_id, s.spot_number, s.status
		FROM parking_zones z
		LEFT JOIN parking_spots s ON s.zone_id = z.id
		ORDER BY z.id, s.spot_number
	`)

	if err != nil {
		return nil, err
	}
	defer rows.Close()

	zones := map[int]*model.ZoneWithSpots{}

	for rows.Next() {

		var zoneID int
		var zoneName string
		var spot model.SpotDTO

		err := rows.Scan(
			&zoneID,
			&zoneName,
			&spot.ID,
			&spot.ZoneID,
			&spot.SpotNumber,
			&spot.Status,
		)

		if err != nil {
			return nil, err
		}

		if _, ok := zones[zoneID]; !ok {
			zones[zoneID] = &model.ZoneWithSpots{
				ID:    zoneID,
				Name:  zoneName,
				Spots: []model.SpotDTO{},
			}
		}

		zones[zoneID].Spots = append(zones[zoneID].Spots, spot)
	}

	result := []model.ZoneWithSpots{}

	for _, z := range zones {
		result = append(result, *z)
	}

	return result, nil

	
}

var _ service.ParkingRepository = (*ParkingRepository)(nil)
