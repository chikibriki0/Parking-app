package model

import "time"

type ParkingSpot struct {
	ID    int
	State string
}

type ParkingManager struct {
	Spots  map[int]*ParkingSpot
	Events chan Event
}

func NewParkingManager() *ParkingManager {
	m := &ParkingManager{
		Spots:  make(map[int]*ParkingSpot),
		Events: make(chan Event),
	}

	for i := 1; i <= 10; i++ {
		m.Spots[i] = &ParkingSpot{
			ID:    i,
			State: "FREE",
		}
	}

	go m.run()

	return m
}

func (m *ParkingManager) run() {
	for event := range m.Events {
		switch event.Type {

		case ReserveEvent:
			spot := m.Spots[event.SpotID]
			if spot.State == "FREE" {
				spot.State = "RESERVED"

				go func(id int) {
					time.Sleep(20 * time.Second)
					m.Events <- Event{Type: ExpireEvent, SpotID: id}
				}(event.SpotID)
			}

		case ReleaseEvent:
			spot := m.Spots[event.SpotID]
			spot.State = "FREE"

		case ExpireEvent:
			spot := m.Spots[event.SpotID]
			if spot.State == "RESERVED" {
				spot.State = "FREE"
			}
		}
	}
}
