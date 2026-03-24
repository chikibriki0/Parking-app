package repository

import (
	"context"
	"fmt"
	"time"
	"log"
	"github.com/jackc/pgx/v5/pgxpool"
)

func NewDB() (*pgxpool.Pool, error) {

	dsn := "postgres://postgres:postgres@postgres:5432/parking_db?sslmode=disable"

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
	log.Println("DB CONNECTED TO:", dsn)
	return nil, err
}