package repository

import (
	"context"
	"errors"
	"time"
	"parking-service/internal/model"
	"github.com/jackc/pgx/v5/pgxpool"
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

	ctx := context.Background()
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var status string
	err = tx.QueryRow(ctx,
		`SELECT status FROM parking_spots WHERE id = $1 FOR UPDATE`,
		spotID,
	).Scan(&status)
	if err != nil {
		return err
	}

	if status == "OCCUPIED" {
		return errors.New("spot already occupied")
	}

	_, err = tx.Exec(ctx,
		`UPDATE parking_spots SET status = 'OCCUPIED' WHERE id = $1`,
		spotID,
	)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx,
		`INSERT INTO parking_history (user_id, spot_id, start_time, source)
		 VALUES ($1, $2, $3, $4)`,
		userID, spotID, start, source,
	)
	if err != nil {
		return err
	}

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

	cmd, err := tx.Exec(ctx,
		`UPDATE parking_history
		 SET end_time = $1
		 WHERE spot_id = $2 AND end_time IS NULL`,
		end, spotID,
	)
	if err != nil {
		return err
	}

	if cmd.RowsAffected() == 0 {
		return errors.New("no active parking session")
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

