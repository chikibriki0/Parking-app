package model

import (
	"math/rand"
	"time"
)


type ParkingSpot struct {
	ID    int    `json:"id"`
	State string `json:"state"`
}


type ParkingManager struct {
	Zones  map[int]*Zone
	Events chan Event
}

func NewParkingManager() *ParkingManager {
	m := &ParkingManager{
		Zones:  make(map[int]*Zone),
		Events: make(chan Event),
	}

	// создаём 2 зоны по 5 мест
	for z := 1; z <= 2; z++ {
		zone := &Zone{
			ID:    z,
			Spots: make(map[int]*ParkingSpot),
		}

		for i := 1; i <= 5; i++ {
			spotID := (z-1)*5 + i
			zone.Spots[spotID] = &ParkingSpot{
				ID:    spotID,
				State: "FREE",
			}
		}

		m.Zones[z] = zone
	}

	go m.run()
	go m.simulateTraffic()

	return m
}

func (m *ParkingManager) run() {
	for event := range m.Events {

		spot := m.findSpot(event.SpotID)
		if spot == nil {
			continue
		}

		switch event.Type {

		case ReserveEvent:
			if spot.State == "FREE" {
				spot.State = "OCCUPIED"

				// случайное время стоянки 10–30 секунд
				duration := time.Duration(rand.Intn(20)+10) * time.Second

				go func(id int, d time.Duration) {
					time.Sleep(d)
					m.Events <- Event{Type: ReleaseEvent, SpotID: id}
				}(event.SpotID, duration)
			}


		case ReleaseEvent:
			spot.State = "FREE"

		case ExpireEvent:
			if spot.State == "RESERVED" {
				spot.State = "FREE"
			}
		}
	}
}

func (m *ParkingManager) findSpot(id int) *ParkingSpot {
	for _, zone := range m.Zones {
		if spot, ok := zone.Spots[id]; ok {
			return spot
		}
	}
	return nil
}

func (m *ParkingManager) simulateTraffic() {
	for {
		interval := time.Duration(rand.Intn(5)+1) * time.Second
		time.Sleep(interval)

		// случайное место от 1 до 10
		spotID := rand.Intn(10) + 1

		spot := m.findSpot(spotID)
		if spot == nil {
			continue
		}

		if spot.State == "FREE" {
			m.Events <- Event{Type: ReserveEvent, SpotID: spotID}
		} else if spot.State == "OCCUPIED" {
			m.Events <- Event{Type: ReleaseEvent, SpotID: spotID}
		}
	}
}

