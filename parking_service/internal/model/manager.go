package model

import (
	"math/rand"
	"time"
)

// ParkingManager оркестрирует поток событий от симуляции.
// Пользовательские и админские события идут синхронно через сервис.
type ParkingManager struct {
	Events    chan Event
	SpotIDs   []int
	spotState map[int]string // FREE | OCCUPIED
}

func NewParkingManager(spotIDs []int) *ParkingManager {
	state := make(map[int]string, len(spotIDs))
	for _, id := range spotIDs {
		state[id] = "FREE"
	}

	return &ParkingManager{
		Events:    make(chan Event, 100),
		SpotIDs:   spotIDs,
		spotState: state,
	}
}

// SimulateTraffic эмулирует поток событий резерв/освобождение в случайные моменты.
// Запускайте как горутину: go manager.SimulateTraffic(stop).
func (m *ParkingManager) SimulateTraffic(stop <-chan struct{}) {
	r := rand.New(rand.NewSource(time.Now().UnixNano()))

	for {
		select {
		case <-stop:
			return
		case <-time.After(time.Duration(r.Intn(3)+2) * time.Second):
		}

		if len(m.SpotIDs) == 0 {
			continue
		}

		id := m.SpotIDs[r.Intn(len(m.SpotIDs))]
		var eventType EventType
		if m.spotState[id] == "FREE" {
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
}
