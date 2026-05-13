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
	// admin
	GetAllUsers() ([]map[string]interface{}, error)
	GetAllActiveSessions() ([]map[string]interface{}, error)
	GetAllParkingHistory() ([]map[string]interface{}, error)
}

type ParkingService struct {
	repo        ParkingRepository
	expireAfter time.Duration
}

func NewParkingService(repo ParkingRepository) *ParkingService {
	return &ParkingService{
		repo:        repo,
		expireAfter: 2 * time.Minute,
	}
}

func (s *ParkingService) HandleEvent(e model.Event) error {
	switch e.Type {

	case model.ReserveEvent:
		if err := s.repo.StartParking(e.UserID, e.SpotID, e.Timestamp, e.Source); err != nil {
			log.Println("START PARKING ERROR:", err)
			return err
		}
		go func(spotID int) {
			time.Sleep(s.expireAfter)
			if err := s.repo.EndParking(spotID, time.Now()); err == nil {
				log.Printf("[EXPIRE] spot %d expired", spotID)
			}
		}(e.SpotID)
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