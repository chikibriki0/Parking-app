package model

import "time"

type User struct {
	ID        int
	Email     string
	Password  string
	Role      string
	CreatedAt time.Time
}
