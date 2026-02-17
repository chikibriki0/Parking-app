package model

type EventType int

const (
	ReserveEvent EventType = iota
	ReleaseEvent
	ExpireEvent
)

type Event struct {
	Type   EventType
	SpotID int
}
