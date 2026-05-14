package service

import (
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var (
	jwtSecret []byte
	jwtTTL    = 24 * time.Hour
)

func InitJWT(secret []byte, ttl time.Duration) {
	jwtSecret = secret
	if ttl > 0 {
		jwtTTL = ttl
	}
}

func GenerateToken(userID int, role string) (string, error) {
	claims := jwt.MapClaims{
		"user_id": userID,
		"role":    role,
		"exp":     time.Now().Add(jwtTTL).Unix(),
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)

	return token.SignedString(jwtSecret)
}
