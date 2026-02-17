package main

import (
	"encoding/json"
	"net/http"
	"golang/model"
	"strconv"
	"strings"
)

func main() {
	manager := model.NewParkingManager()

	http.HandleFunc("/spots", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		spots := []model.ParkingSpot{}
		for _, s := range manager.Spots {
			spots = append(spots, *s)
		}

		json.NewEncoder(w).Encode(spots)
	})

	http.HandleFunc("/reserve/", func(w http.ResponseWriter, r *http.Request) {
		idStr := strings.TrimPrefix(r.URL.Path, "/reserve/")
		id, _ := strconv.Atoi(idStr)

		manager.Events <- model.Event{
			Type:   model.ReserveEvent,
			SpotID: id,
		}

		w.Write([]byte("Reservation requested"))
	})

	http.ListenAndServe(":8080", nil)
}
