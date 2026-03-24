package model

import (
	"math/rand"
	"time"
)

type ParkingManager struct {
	Events    chan Event
	SpotIDs   []int
	spotState map[int]string // локальное состояние: FREE / OCCUPIED
}

func NewParkingManager(spotIDs []int) *ParkingManager {
	state := make(map[int]string)

	// все места изначально свободны
	for _, id := range spotIDs {
		state[id] = "FREE"
	}

	return &ParkingManager{
		Events:    make(chan Event, 100),
		SpotIDs:   spotIDs,
		spotState: state,
	}
}

// Умная симуляция
func (m *ParkingManager) SimulateTraffic() {
	go func() {
		rand.Seed(time.Now().UnixNano())

		for {
			time.Sleep(time.Duration(rand.Intn(3)+2) * time.Second)

			if len(m.SpotIDs) == 0 {
				continue
			}

			id := m.SpotIDs[rand.Intn(len(m.SpotIDs))]

			currentState := m.spotState[id]

			var eventType EventType

			// 🔥 умная логика
			if currentState == "FREE" {
				eventType = ReserveEvent
				m.spotState[id] = "OCCUPIED"
			} else {
				eventType = ReleaseEvent
				m.spotState[id] = "FREE"
			}

			m.Events <- Event{
				Type:      eventType,
				SpotID:    id,
				Source:    SourceSimulation,
				Timestamp: time.Now(),
			}
		}
	}()
}