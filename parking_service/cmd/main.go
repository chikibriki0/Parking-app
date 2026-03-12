// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization
// @title Parking Service API
// @version 1.0
// @description API сервиса управления парковочными местами
// @host localhost:8080
// @BasePath /
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
import httpSwagger "github.com/swaggo/http-swagger"
import _ "parking-service/docs"


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
	/*manager.SimulateTraffic()*/


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

	// Reserve parking spot
	// @Summary Резервирование парковочного места
	// @Description Резервирует парковочное место по ID
	// @Tags parking
	// @Produce json
	// @Param id path int true "ID парковочного места"
	// @Success 200 {string} string "Reservation requested"
	// @Security BearerAuth
	// @Router /reserve/{id} [post]
	reserveHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

		idStr := strings.TrimPrefix(r.URL.Path, "/reserve/")
		id, err := strconv.Atoi(idStr)
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		userID := r.Context().Value(service.UserIDKey).(int)
		log.Println("USER ID FROM TOKEN:", userID)

		manager.Events <- model.Event{
			Type:      model.ReserveEvent,
			SpotID:    id,
			UserID:    &userID,
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


	// Login godoc
	// @Summary Авторизация пользователя
	// @Description Выполняет вход пользователя и возвращает JWT токен
	// @Tags auth
	// @Accept json
	// @Produce json
	// @Param request body object true "Email и пароль"
	// @Success 200 {object} map[string]string
	// @Failure 401 {string} string "Invalid credentials"
	// @Router /login [post]
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
	myParkingHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

	userID := r.Context().Value(service.UserIDKey).(int)
	log.Println("USER ID FROM TOKEN:", userID)

	spotID, startTime, err := parkingService.GetActiveParking(userID)
	if err != nil {
		http.Error(w, "No active parking", http.StatusNotFound)
		return
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"spot_id":    spotID,
		"start_time": startTime,
	})
})


statsHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

	total, occupied, free, err := parkingService.GetStats()
	if err != nil {
		http.Error(w, "Failed to get stats", http.StatusInternalServerError)
		return
	}

	json.NewEncoder(w).Encode(map[string]int{
		"total_spots": total,
		"occupied":    occupied,
		"free":        free,
	})
})

http.Handle("/stats", statsHandler)


myHistoryHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

	userID := r.Context().Value(service.UserIDKey).(int)
	log.Println("USER ID FROM TOKEN:", userID)

	history, err := parkingService.GetUserHistory(userID)
	if err != nil {
		http.Error(w, "Failed to get history", http.StatusInternalServerError)
		return
	}

	json.NewEncoder(w).Encode(history)
})

http.HandleFunc("/zones/", func(w http.ResponseWriter, r *http.Request) {

	if !strings.HasSuffix(r.URL.Path, "/spots") {
		http.NotFound(w, r)
		return
	}

	parts := strings.Split(r.URL.Path, "/")

	if len(parts) < 3 {
		http.Error(w, "invalid zone id", http.StatusBadRequest)
		return
	}

	zoneID, err := strconv.Atoi(parts[2])
	if err != nil {
		http.Error(w, "invalid zone id", http.StatusBadRequest)
		return
	}

	spots, err := parkingRepo.GetSpotsByZone(zoneID)
	if err != nil {
		http.Error(w, "server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(spots)
})

http.Handle("/my/history", service.JWTMiddleware(myHistoryHandler))


http.Handle("/my/parking", service.JWTMiddleware(myParkingHandler))

// Get parking map
// @Summary Получить карту парковки
// @Description Возвращает все зоны и парковочные места
// @Tags parking
// @Produce json
// @Success 200 {object} model.ParkingMap
// @Router /parking/map [get]
http.HandleFunc("/parking/map", func(w http.ResponseWriter, r *http.Request) {

	zones, err := parkingRepo.GetParkingMap()
	if err != nil {
		http.Error(w, "server error", http.StatusInternalServerError)
		return
	}

	resp := model.ParkingMap{
		Zones: zones,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
})


	http.Handle("/swagger/", httpSwagger.WrapHandler)

	log.Println("🚀 Server started on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))

	
}


