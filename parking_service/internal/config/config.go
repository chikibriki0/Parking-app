package config

import (
	"log"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	HTTPAddr        string
	DatabaseURL     string
	JWTSecret       []byte
	JWTTTL          time.Duration
	ParkingExpireAfter time.Duration
	SimulationEnabled bool
	CORSAllowedOrigins []string
}

func Load() *Config {
	cfg := &Config{
		HTTPAddr:           getEnv("HTTP_ADDR", ":8080"),
		DatabaseURL:        getEnv("DATABASE_URL", "postgres://postgres:postgres@postgres:5432/parking_db?sslmode=disable"),
		JWTSecret:          []byte(getEnv("JWT_SECRET", "")),
		JWTTTL:             getDuration("JWT_TTL", 24*time.Hour),
		ParkingExpireAfter: getDuration("PARKING_EXPIRE_AFTER", 2*time.Minute),
		SimulationEnabled:  getBool("SIMULATION_ENABLED", false),
		CORSAllowedOrigins: splitCSV(getEnv("CORS_ALLOWED_ORIGINS", "*")),
	}

	if len(cfg.JWTSecret) == 0 {
		log.Fatal("JWT_SECRET environment variable is required and must not be empty")
	}
	if len(cfg.JWTSecret) < 32 {
		log.Println("WARNING: JWT_SECRET is shorter than 32 bytes — consider using a longer secret in production")
	}

	return cfg
}

func getEnv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok {
		return v
	}
	return fallback
}

func getDuration(key string, fallback time.Duration) time.Duration {
	v, ok := os.LookupEnv(key)
	if !ok {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		log.Printf("invalid duration for %s=%q, using default %s", key, v, fallback)
		return fallback
	}
	return d
}

func getBool(key string, fallback bool) bool {
	v, ok := os.LookupEnv(key)
	if !ok {
		return fallback
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		log.Printf("invalid bool for %s=%q, using default %v", key, v, fallback)
		return fallback
	}
	return b
}

func splitCSV(s string) []string {
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}
