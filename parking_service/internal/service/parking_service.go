package service

import (
	"errors"
	"log"
	"time"

	"parking-service/internal/model"
)

type ParkingRepository interface {
	StartParking(userID *int, spotID int, start time.Time, duration time.Duration, source string) error
	EndParking(spotID int, end time.Time) error
	ExtendUserParking(userID int, additional time.Duration, maxTotal time.Duration) (newExpires time.Time, err error)
	GetActiveParking(userID int) (spotID int, startTime time.Time, expiresAt time.Time, err error)
	GetUserHistory(userID int) ([]map[string]interface{}, error)
	GetStats() (int, int, int, error)
	ExpireDueSessions(now time.Time) ([]int, error)
	HasActiveUserSession(spotID int) (bool, error)
	// admin
	GetAllUsers() ([]map[string]interface{}, error)
	GetAllActiveSessions() ([]map[string]interface{}, error)
	GetAllParkingHistory() ([]map[string]interface{}, error)
}

type ParkingService struct {
	repo               ParkingRepository
	DefaultExpireAfter time.Duration
}

func NewParkingService(repo ParkingRepository, expireAfter time.Duration) *ParkingService {
	return &ParkingService{
		repo:               repo,
		DefaultExpireAfter: expireAfter,
	}
}

// HandleEvent applies a parking event synchronously and returns any error
// (typed sentinel errors are defined in errors.go).
// Duration must be set on Event.Duration (zero falls back to DefaultExpireAfter).
func (s *ParkingService) HandleEvent(e model.Event) error {
	switch e.Type {
	case model.ReserveEvent:
		dur := e.Duration
		if dur <= 0 {
			dur = s.DefaultExpireAfter
		}
		if err := s.repo.StartParking(e.UserID, e.SpotID, e.Timestamp, dur, e.Source); err != nil {
			if !isTypedClientError(err) {
				log.Println("START PARKING ERROR:", err)
			}
			return err
		}
		return nil

	case model.ReleaseEvent, model.ExpireEvent:
		// Симуляция держит локальное состояние мест и иногда «теряет
		// синхронизацию» с БД — например, помечает место занятым,
		// хотя бронь принадлежит реальному пользователю. Защита: симулятор
		// никогда не освобождает места с активной пользовательской сессией.
		if e.Source == model.SourceSimulation {
			hasUser, qErr := s.repo.HasActiveUserSession(e.SpotID)
			if qErr == nil && hasUser {
				return nil
			}
		}
		err := s.repo.EndParking(e.SpotID, e.Timestamp)
		if err != nil {
			return err
		}
		return nil
	}

	return nil
}

func isTypedClientError(err error) bool {
	return errors.Is(err, ErrUserHasActiveParking) ||
		errors.Is(err, ErrSpotOccupied) ||
		errors.Is(err, ErrSpotNotFound) ||
		errors.Is(err, ErrNoActiveParking)
}

// StartExpirationSweeper periodically завершает сессии, у которых истёк
// per-session expires_at. Переживает перезапуски сервера.
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
				expired, err := s.repo.ExpireDueSessions(now)
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

func (s *ParkingService) GetActiveParking(userID int) (int, time.Time, time.Time, error) {
	return s.repo.GetActiveParking(userID)
}

// ExtendUserParking продлевает активную бронь пользователя на additional.
// maxTotal — максимально допустимая суммарная длительность брони (от start_time).
func (s *ParkingService) ExtendUserParking(userID int, additional time.Duration) (time.Time, error) {
	const maxTotalDuration = 24 * time.Hour
	return s.repo.ExtendUserParking(userID, additional, maxTotalDuration)
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
