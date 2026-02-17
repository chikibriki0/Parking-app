package repository

import (
	"context"
	"fmt"

	//"os"

	"github.com/jackc/pgx/v5/pgxpool"
)

func NewDB() (*pgxpool.Pool, error) {
	dsn := "postgres://postgres:2004@localhost:5432/parking_service?sslmode=disable"

	dbpool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		return nil, err
	}

	if err := dbpool.Ping(context.Background()); err != nil {
		return nil, err
	}

	fmt.Println("Connected to PostgreSQL")
	return dbpool, nil
}
