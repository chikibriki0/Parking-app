package service

import (
	"log"
	"time"

	"parking-service/internal/model"
)

// 🔹 Абстракция хранилища
type ParkingRepository interface {
	StartParking(userID *int, spotID int, start time.Time, source string) error
	EndParking(spotID int, end time.Time) error
}

// 🔹 Сервис бизнес-логики
type ParkingService struct {
	repo        ParkingRepository
	expireAfter time.Duration
}

// 🔹 Конструктор
func NewParkingService(repo ParkingRepository) *ParkingService {
	return &ParkingService{
		repo:        repo,
		expireAfter: 2 * time.Minute, // позже вынесем в env
	}
}

// 🔹 Обработка событий
func (s *ParkingService) HandleEvent(e model.Event) error {
	switch e.Type {

	case model.ReserveEvent:
		// старт парковки
		if err := s.repo.StartParking(
			e.UserID,
			e.SpotID,
			e.Timestamp,
			e.Source,
		); err != nil {
			return err
		}

		// ⏱ автоистечение
		go func(spotID int) {
			time.Sleep(s.expireAfter)

			if err := s.repo.EndParking(spotID, time.Now()); err == nil {
				log.Printf("[EXPIRE] spot %d expired", spotID)
			}
		}(e.SpotID)

		return nil

	case model.ReleaseEvent, model.ExpireEvent:
		return s.repo.EndParking(
			e.SpotID,
			e.Timestamp,
		)
	}

	return nil
}
