package repository

import (
	"context"
	"parking-service/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type UserRepository struct {
	db *pgxpool.Pool
}

func NewUserRepository(db *pgxpool.Pool) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) Create(user *model.User) error {
	query := `
		INSERT INTO users (email, password, role)
		VALUES ($1, $2, $3)
		RETURNING id, created_at
	`

	return r.db.QueryRow(context.Background(), query,
		user.Email,
		user.Password,
		user.Role,
	).Scan(&user.ID, &user.CreatedAt)
}

func (r *UserRepository) FindByEmail(email string) (*model.User, error) {
	query := `
		SELECT id, email, password, role, created_at
		FROM users
		WHERE email = $1
	`

	user := &model.User{}
	err := r.db.QueryRow(context.Background(), query, email).
		Scan(&user.ID, &user.Email, &user.Password, &user.Role, &user.CreatedAt)

	if err != nil {
		return nil, err
	}

	return user, nil
}
