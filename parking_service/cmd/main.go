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
	"github.com/rs/cors"
	"golang.org/x/crypto/bcrypt"

	"parking-service/internal/model"
	"parking-service/internal/repository"
	"parking-service/internal/service"

	httpSwagger "github.com/swaggo/http-swagger"

	_ "parking-service/docs"
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
	go manager.SimulateTraffic()

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

			data := map[string]interface{}{
				"spot_id": event.SpotID,
				"type":    event.Type,
				"source":  event.Source,
			}

			jsonData, _ := json.Marshal(data)
			service.Broadcast(jsonData)
		}
	}()


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

	// 👇 ВОТ ЭТО ДОБАВИТЬ
	userID := r.Context().Value(service.UserIDKey).(int)

	manager.Events <- model.Event{
		Type:      model.ReleaseEvent,
		SpotID:    id,
		UserID:    &userID, // 🔥 КЛЮЧЕВОЕ
		Source:    model.SourceUser,
		Timestamp: time.Now(),
	}

	w.Write([]byte("Release requested"))
})

	http.Handle("/release/", service.JWTMiddleware(releaseHandler))

	

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
			http.Error(w, "Invalid request", http.StatusBadRequest)
			return
		}

		hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
		if err != nil {
			http.Error(w, "Password error", http.StatusInternalServerError)
			return
		}

		user := &model.User{
			Email:    req.Email,
			Password: string(hash),
			Role:     "USER",
		}

		if err := userRepo.Create(user); err != nil {

			if strings.Contains(err.Error(), "duplicate") {
				http.Error(w, "User already exists", http.StatusConflict)
				return
			}

			http.Error(w, "Server error", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(user)
	})

	http.HandleFunc("/login", func(w http.ResponseWriter, r *http.Request) {
		LoginHandler(userRepo, w, r)
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
			log.Println("GET STATS ERROR:", err) // 👈 ВОТ ЭТО КЛЮЧ
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

	http.HandleFunc("/parking/map", func(w http.ResponseWriter, r *http.Request) {
	ParkingMapHandler(parkingRepo, w, r)
})

	http.Handle("/reserve/", service.JWTMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}

		ReserveHandler(manager, w, r)

	})))

	http.Handle("/swagger/", httpSwagger.WrapHandler)

	http.HandleFunc("/ws", service.WSHandler)

	log.Println("🚀 Server started on :8080")
		c := cors.New(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"*"},
		AllowCredentials: true,
	})

	handler := c.Handler(http.DefaultServeMux)

	log.Println("🚀 Server started on :8080")
	log.Fatal(http.ListenAndServe(":8080", handler))

}




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
func LoginHandler(userRepo *repository.UserRepository, w http.ResponseWriter, r *http.Request) {

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

	log.Println("EMAIL:", req.Email)
	log.Println("PASSWORD FROM REQUEST:", req.Password)

	user, err := userRepo.FindByEmail(req.Email)
	if err != nil || user == nil {
		http.Error(w, "Invalid credentials", http.StatusUnauthorized)
		return
	}

	log.Println("HASH FROM DB:", user.Password)
	log.Println("COMPARE ERROR:", err)

	err = bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password))
	if err != nil {
		http.Error(w, "Invalid credentials", http.StatusUnauthorized)
		return
	}

	token, err := service.GenerateToken(user.ID, user.Role)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	json.NewEncoder(w).Encode(map[string]string{"token": token})
}


// Get parking map
// @Summary Получить карту парковки
// @Description Возвращает все зоны и парковочные места
// @Tags parking
// @Produce json
// @Success 200 {object} model.ParkingMap
// @Router /parking/map [get]
func ParkingMapHandler(parkingRepo *repository.ParkingRepository, w http.ResponseWriter, r *http.Request) {

	zones, err := parkingRepo.GetParkingMap()
	if err != nil {
		http.Error(w, "server error", http.StatusInternalServerError)
		return
	}

	resp := model.ParkingMap{
		Zones: zones,
	}

	json.NewEncoder(w).Encode(resp)
}



	// Reserve parking spot
// @Summary Резервирование парковочного места
// @Description Резервирует парковочное место по ID
// @Tags parking
// @Produce json
// @Param id path int true "ID парковочного места"
// @Success 200 {string} string "Reservation requested"
// @Security BearerAuth
// @Router /reserve/{id} [post]
func ReserveHandler(manager *model.ParkingManager, w http.ResponseWriter, r *http.Request) {

	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	idStr := strings.TrimPrefix(r.URL.Path, "/reserve/")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	userID := r.Context().Value(service.UserIDKey).(int)

	manager.Events <- model.Event{
		Type:      model.ReserveEvent,
		SpotID:    id,
		UserID:    &userID,
		Source:    model.SourceUser,
		Timestamp: time.Now(),
	}

	w.Write([]byte("Reservation requested"))
}
