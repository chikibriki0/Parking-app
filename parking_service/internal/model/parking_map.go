package model

type ZoneWithSpots struct {
	ID    int       `json:"id"`
	Name  string    `json:"name"`
	Spots []SpotDTO `json:"spots"`
}

type ParkingMap struct {
	Zones []ZoneWithSpots `json:"zones"`
}