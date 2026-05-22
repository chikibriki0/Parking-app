package service

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// resetJWT — общая инициализация секрета для тестов.
// Эти тесты изолированы (один и тот же секрет в рамках пакета).
func resetJWT(t *testing.T) {
	t.Helper()
	InitJWT([]byte("unit-test-secret-do-not-use-in-prod"), time.Hour)
}

func TestGenerateToken_ContainsExpectedClaims(t *testing.T) {
	resetJWT(t)

	tokenStr, err := GenerateToken(123, "ADMIN")
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}

	parsed, err := jwt.Parse(tokenStr, func(*jwt.Token) (interface{}, error) {
		return jwtSecret, nil
	})
	if err != nil {
		t.Fatalf("token failed to parse: %v", err)
	}
	claims, ok := parsed.Claims.(jwt.MapClaims)
	if !ok || !parsed.Valid {
		t.Fatalf("expected valid MapClaims")
	}
	if uid, _ := claims["user_id"].(float64); int(uid) != 123 {
		t.Errorf("expected user_id=123, got %v", claims["user_id"])
	}
	if role, _ := claims["role"].(string); role != "ADMIN" {
		t.Errorf("expected role=ADMIN, got %v", claims["role"])
	}
	if _, ok := claims["exp"]; !ok {
		t.Error("expected exp claim")
	}
}

func TestGenerateToken_ExpRespectsTTL(t *testing.T) {
	InitJWT([]byte("secret-1234567890"), 10*time.Minute)
	before := time.Now()
	tokenStr, err := GenerateToken(1, "USER")
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}
	parsed, _ := jwt.Parse(tokenStr, func(*jwt.Token) (interface{}, error) {
		return jwtSecret, nil
	})
	claims := parsed.Claims.(jwt.MapClaims)
	exp := int64(claims["exp"].(float64))
	delta := exp - before.Unix()
	// ttl 10m → exp должен быть в районе now+600s, допускаем ±5 секунд.
	if delta < 595 || delta > 605 {
		t.Errorf("expected exp ≈ now+600s, got delta=%d", delta)
	}
}

func TestParseToken_DifferentSecretFails(t *testing.T) {
	// Генерируем токен одним секретом, парсим другим — должны получить ошибку.
	InitJWT([]byte("secret-a"), time.Hour)
	tokenStr, _ := GenerateToken(1, "USER")

	_, err := jwt.Parse(tokenStr, func(*jwt.Token) (interface{}, error) {
		return []byte("secret-b"), nil
	})
	if err == nil {
		t.Error("expected parse error with wrong secret, got nil")
	}
}
