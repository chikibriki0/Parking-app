package model

import "time"

type EventType int

const (
	ReserveEvent EventType = iota
	ReleaseEvent
	ExpireEvent
)

const (
	SourceUser       = "USER"
	SourceSimulation = "SIMULATION"
)

type Event struct {
	Type      EventType
	SpotID    int
	UserID    *int
	Timestamp time.Time
	Source    string // USER | SIMULATION
}
