package model

type SpotDTO struct {
	ID         int    `json:"id"`
	ZoneID     int    `json:"zone_id"`
	SpotNumber int    `json:"spot_number"`
	Status     string `json:"status"`
}
