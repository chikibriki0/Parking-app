package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func NewDB(dsn string) (*pgxpool.Pool, error) {
	var dbpool *pgxpool.Pool
	var err error

	for i := 0; i < 10; i++ {
		dbpool, err = pgxpool.New(context.Background(), dsn)
		if err == nil {
			err = dbpool.Ping(context.Background())
			if err == nil {
				fmt.Println("Connected to PostgreSQL")
				return dbpool, nil
			}
		}

		fmt.Println("Waiting for PostgreSQL...")
		time.Sleep(2 * time.Second)
	}
	return nil, fmt.Errorf("failed to connect to PostgreSQL after retries: %w", err)
}
