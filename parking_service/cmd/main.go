package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"
	"golang.org/x/crypto/bcrypt"

	"parking-service/internal/model"
	"parking-service/internal/repository"
	"parking-service/internal/service"
)

func main() {

	// 🔹 Подключение к базе данных
	db, err := repository.NewDB()
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// 🔹 Репозитории и сервисы
	userRepo := repository.NewUserRepository(db)
	parkingRepo := repository.NewParkingRepository(db)
	parkingService := service.NewParkingService(parkingRepo)

	// 🔹 Parking manager (ЕДИНСТВЕННЫЙ)
	spotIDs, err := parkingRepo.GetAllSpotIDs()
	if err != nil {
		log.Fatal(err)
	}

	manager := model.NewParkingManager(spotIDs)
	manager.SimulateTraffic()


		http.HandleFunc("/spots", func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodGet {
				w.WriteHeader(http.StatusMethodNotAllowed)
				return
			}

			w.Header().Set("Content-Type", "application/json")

			spots, err := parkingRepo.GetAllSpots()
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}

			json.NewEncoder(w).Encode(spots)
		})

	// 🔹 Event-loop: model → service → DB
	go func() {
		for event := range manager.Events {

			log.Printf(
				"[EVENT] type=%v spot=%d source=%q",
				event.Type,
				event.SpotID,
				event.Source,
			)

			if err := parkingService.HandleEvent(event); err != nil {
				log.Println("parking event error:", err)
			}
		}
	}()

	// 🔹 Резервирование (через событие)
	reserveHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

		idStr := strings.TrimPrefix(r.URL.Path, "/reserve/")
		id, err := strconv.Atoi(idStr)
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		manager.Events <- model.Event{
			Type:      model.ReserveEvent,
			SpotID:    id,
			Source:    model.SourceUser,
			Timestamp: time.Now(),
		}

		w.Write([]byte("Reservation requested"))
	})

	http.Handle("/reserve/", service.JWTMiddleware(reserveHandler))
	
	releaseHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}

		idStr := strings.TrimPrefix(r.URL.Path, "/release/")
		id, err := strconv.Atoi(idStr)
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		manager.Events <- model.Event{
			Type:      model.ReleaseEvent,
			SpotID:    id,
			Source:    model.SourceUser,
			Timestamp: time.Now(),
		}

		w.Write([]byte("Release requested"))
	})

	http.Handle("/release/", service.JWTMiddleware(releaseHandler))

	// 🔹 Login
	http.HandleFunc("/login", func(w http.ResponseWriter, r *http.Request) {

		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}

		var req struct {
			Email    string `json:"email"`
			Password string `json:"password"`
		}

		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		user, err := userRepo.FindByEmail(req.Email)
		if err != nil {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}

		if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password)); err != nil {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}

		token, err := service.GenerateToken(user.ID, user.Role)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		json.NewEncoder(w).Encode(map[string]string{"token": token})
	})

	
	// 🔹 Register
	http.HandleFunc("/register", func(w http.ResponseWriter, r *http.Request) {

		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}

		var req struct {
			Email    string `json:"email"`
			Password string `json:"password"`
		}

		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		hash, _ := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)

		user := &model.User{
			Email:    req.Email,
			Password: string(hash),
			Role:     "USER",
		}

		if err := userRepo.Create(user); err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(user)
	})

	log.Println("🚀 Server started on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
