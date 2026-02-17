package model

type Zone struct {
	ID    int
	Spots map[int]*ParkingSpot
}
