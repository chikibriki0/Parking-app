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

// maxOccupancyRatio — верхний предел занятости, выше которого симуляция
// перестаёт занимать новые места и только освобождает. Делает картинку
// похожей на реальную парковку и оставляет места для интерактивного
// тестирования живым пользователем.
const maxOccupancyRatio = 0.5

// RollbackLocalState откатывает локальный spotState, если событие
// симуляции не было применено в БД (например, место уже занято
// пользователем). Иначе симулятор будет «думать», что место занято
// им, и через несколько секунд попытается его освободить — что снесёт
// пользовательскую бронь.
func (m *ParkingManager) RollbackLocalState(e Event) {
	switch e.Type {
	case ReserveEvent:
		m.spotState[e.SpotID] = "FREE"
	case ReleaseEvent:
		m.spotState[e.SpotID] = "OCCUPIED"
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
		case <-time.After(time.Duration(r.Intn(3)+3) * time.Second):
		}

		if len(m.SpotIDs) == 0 {
			continue
		}

		occupied := 0
		for _, st := range m.spotState {
			if st == "OCCUPIED" {
				occupied++
			}
		}
		ratio := float64(occupied) / float64(len(m.SpotIDs))

		id := m.SpotIDs[r.Intn(len(m.SpotIDs))]
		var eventType EventType
		switch {
		case m.spotState[id] == "OCCUPIED":
			eventType = ReleaseEvent
			m.spotState[id] = "FREE"
		case ratio >= maxOccupancyRatio:
			// уже плотно занято — пропускаем тик, ждём пока кто-то освободится
			continue
		default:
			eventType = ReserveEvent
			m.spotState[id] = "OCCUPIED"
		}

		m.Events <- Event{
			Type:      eventType,
			SpotID:    id,
			Source:    SourceSimulation,
			Timestamp: time.Now(),
		}
	}
}
