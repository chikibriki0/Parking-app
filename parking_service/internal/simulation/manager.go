package simulation

import "parking-service/internal/model"


type ParkingManager struct {
	EventChan chan model.ParkingEvent
	// остальное без изменений
}
