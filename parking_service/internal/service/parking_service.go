package service

import (
	"errors"
	"log"
	"time"

	"github.com/jackc/pgx/v5"

	"parking-service/internal/model"
)

type ParkingRepository interface {
	StartParking(userID *int, spotID int, start time.Time, source string) error
	EndParking(spotID int, end time.Time) error
	GetActiveParking(userID int) (int, time.Time, error)
	GetUserHistory(userID int) ([]map[string]interface{}, error)
	GetStats() (int, int, int, error)
	ExpireOldSessions(olderThan time.Time) ([]int, error)
	// admin
	GetAllUsers() ([]map[string]interface{}, error)
	GetAllActiveSessions() ([]map[string]interface{}, error)
	GetAllParkingHistory() ([]map[string]interface{}, error)
}

type ParkingService struct {
	repo        ParkingRepository
	ExpireAfter time.Duration
}

func NewParkingService(repo ParkingRepository, expireAfter time.Duration) *ParkingService {
	return &ParkingService{
		repo:        repo,
		ExpireAfter: expireAfter,
	}
}

// HandleEvent applies a parking event synchronously and returns any error
// (typed sentinel errors are defined in errors.go).
func (s *ParkingService) HandleEvent(e model.Event) error {
	switch e.Type {
	case model.ReserveEvent:
		if err := s.repo.StartParking(e.UserID, e.SpotID, e.Timestamp, e.Source); err != nil {
			if !isTypedClientError(err) {
				log.Println("START PARKING ERROR:", err)
			}
			return err
		}
		return nil

	case model.ReleaseEvent, model.ExpireEvent:
		err := s.repo.EndParking(e.SpotID, e.Timestamp)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		return err
	}

	return nil
}

func isTypedClientError(err error) bool {
	return errors.Is(err, ErrUserHasActiveParking) ||
		errors.Is(err, ErrSpotOccupied) ||
		errors.Is(err, ErrSpotNotFound) ||
		errors.Is(err, ErrNoActiveParking)
}

// StartExpirationSweeper runs in background, periodically ending sessions
// older than ExpireAfter. Replaces per-event goroutines so that expirations
// survive server restarts.
func (s *ParkingService) StartExpirationSweeper(interval time.Duration) chan<- struct{} {
	stop := make(chan struct{})
	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case now := <-ticker.C:
				cutoff := now.Add(-s.ExpireAfter)
				expired, err := s.repo.ExpireOldSessions(cutoff)
				if err != nil {
					log.Println("expire sweeper error:", err)
					continue
				}
				if len(expired) > 0 {
					log.Printf("[SWEEPER] expired %d sessions", len(expired))
				}
			}
		}
	}()
	return stop
}

func (s *ParkingService) GetActiveParking(userID int) (int, time.Time, error) {
	return s.repo.GetActiveParking(userID)
}

func (s *ParkingService) GetUserHistory(userID int) ([]map[string]interface{}, error) {
	return s.repo.GetUserHistory(userID)
}

func (s *ParkingService) GetStats() (int, int, int, error) {
	return s.repo.GetStats()
}

func (s *ParkingService) GetAllUsers() ([]map[string]interface{}, error) {
	return s.repo.GetAllUsers()
}

func (s *ParkingService) GetAllActiveSessions() ([]map[string]interface{}, error) {
	return s.repo.GetAllActiveSessions()
}

func (s *ParkingService) GetAllParkingHistory() ([]map[string]interface{}, error) {
	return s.repo.GetAllParkingHistory()
}
