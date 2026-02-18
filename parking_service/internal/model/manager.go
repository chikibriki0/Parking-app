package model

import (
	"math/rand"
	"time"
)

type ParkingManager struct {
	Events  chan Event
	SpotIDs []int
}

func NewParkingManager(spotIDs []int) *ParkingManager {
	return &ParkingManager{
		Events:  make(chan Event, 10),
		SpotIDs: spotIDs,
	}
}

// Имитация трафика (ТОЛЬКО события)
func (m *ParkingManager) SimulateTraffic() {
	go func() {
		for {
			time.Sleep(time.Duration(rand.Intn(5)+1) * time.Second)

			if len(m.SpotIDs) == 0 {
				continue
			}

			id := m.SpotIDs[rand.Intn(len(m.SpotIDs))]

			m.Events <- Event{
				Type:      ReserveEvent,
				SpotID:    id,
				Source:    SourceSimulation,
				Timestamp: time.Now(),
			}
		}
	}()
}
