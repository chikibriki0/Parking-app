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
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/rs/cors"
	"golang.org/x/crypto/bcrypt"

	httpSwagger "github.com/swaggo/http-swagger"

	_ "parking-service/docs"
	"parking-service/internal/model"
	"parking-service/internal/repository"
	"parking-service/internal/service"
)

func main() {
	db, err := repository.NewDB()
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	// Сбрасываем все места в FREE при старте
	db.Exec(context.Background(), `UPDATE parking_spots SET status = 'FREE'`)
	userRepo := repository.NewUserRepository(db)
	parkingRepo := repository.NewParkingRepository(db)
	parkingService := service.NewParkingService(parkingRepo)

	spotIDs, err := parkingRepo.GetAllSpotIDs()
	if err != nil {
		log.Fatal(err)
	}
	manager := model.NewParkingManager(spotIDs)
	go manager.SimulateTraffic()

	// Event-loop
	go func() {
		for event := range manager.Events {
			log.Printf("[EVENT] type=%v spot=%d source=%q",
				event.Type, event.SpotID, event.Source)
			if err := parkingService.HandleEvent(event); err != nil {
				log.Println("parking event error:", err)
			}
			data, _ := json.Marshal(map[string]interface{}{
				"spot_id": event.SpotID,
				"type":    event.Type,
				"source":  event.Source,
			})
			service.Broadcast(data)
		}
	}()

	mux := http.NewServeMux()

	// ── PUBLIC ──────────────────────────────────────────────────────

	mux.HandleFunc("/register", func(w http.ResponseWriter, r *http.Request) {
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
		user := &model.User{Email: req.Email, Password: string(hash), Role: "USER"}
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

	mux.HandleFunc("/login", func(w http.ResponseWriter, r *http.Request) {
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
		if err != nil || user == nil {
			http.Error(w, "Invalid credentials", http.StatusUnauthorized)
			return
		}
		if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password)); err != nil {
			http.Error(w, "Invalid credentials", http.StatusUnauthorized)
			return
		}
		token, err := service.GenerateToken(user.ID, user.Role)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"token": token})
	})

	mux.HandleFunc("/parking/map", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		zones, err := parkingRepo.GetParkingMap()
		if err != nil {
			http.Error(w, "server error", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(model.ParkingMap{Zones: zones})
	})

	mux.HandleFunc("/spots", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		spots, err := parkingRepo.GetAllSpots()
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(spots)
	})

	mux.HandleFunc("/zones/", func(w http.ResponseWriter, r *http.Request) {
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

	mux.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		total, occupied, free, err := parkingService.GetStats()
		if err != nil {
			http.Error(w, "Failed to get stats", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]int{
			"total_spots": total, "occupied": occupied, "free": free,
		})
	})

	mux.HandleFunc("/ws", service.WSHandler)
	mux.Handle("/swagger/", httpSwagger.WrapHandler)

	// ── PROTECTED ───────────────────────────────────────────────────

	mux.Handle("/reserve/", service.JWTMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		id, err := strconv.Atoi(strings.TrimPrefix(r.URL.Path, "/reserve/"))
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		userID := r.Context().Value(service.UserIDKey).(int)
		manager.Events <- model.Event{
			Type: model.ReserveEvent, SpotID: id,
			UserID: &userID, Source: model.SourceUser, Timestamp: time.Now(),
		}
		w.Write([]byte("Reservation requested"))
	})))

	mux.Handle("/release/", service.JWTMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		id, err := strconv.Atoi(strings.TrimPrefix(r.URL.Path, "/release/"))
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		userID := r.Context().Value(service.UserIDKey).(int)
		manager.Events <- model.Event{
			Type: model.ReleaseEvent, SpotID: id,
			UserID: &userID, Source: model.SourceUser, Timestamp: time.Now(),
		}
		w.Write([]byte("Release requested"))
	})))

	mux.Handle("/my/parking", service.JWTMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		userID := r.Context().Value(service.UserIDKey).(int)
		spotID, startTime, err := parkingService.GetActiveParking(userID)
		if err != nil {
			http.Error(w, "No active parking", http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"spot_id": spotID, "start_time": startTime,
		})
	})))

	mux.Handle("/my/history", service.JWTMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		userID := r.Context().Value(service.UserIDKey).(int)
		history, err := parkingService.GetUserHistory(userID)
		if err != nil {
			http.Error(w, "Failed to get history", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(history)
	})))

	// ── ADMIN ───────────────────────────────────────────────────────

	admin := func(h http.Handler) http.Handler {
		return service.JWTMiddleware(service.AdminOnlyMiddleware(h))
	}

	mux.Handle("/admin/users", admin(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		users, err := parkingService.GetAllUsers()
		if err != nil {
			http.Error(w, "server error", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(users)
	})))

	mux.Handle("/admin/active-sessions", admin(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		sessions, err := parkingService.GetAllActiveSessions()
		if err != nil {
			http.Error(w, "server error", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(sessions)
	})))

	mux.Handle("/admin/history", admin(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		history, err := parkingService.GetAllParkingHistory()
		if err != nil {
			http.Error(w, "server error", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(history)
	})))

	mux.Handle("/admin/release/", admin(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		id, err := strconv.Atoi(strings.TrimPrefix(r.URL.Path, "/admin/release/"))
		if err != nil {
			http.Error(w, "invalid spot id", http.StatusBadRequest)
			return
		}
		manager.Events <- model.Event{
			Type: model.ReleaseEvent, SpotID: id,
			Source: "ADMIN", Timestamp: time.Now(),
		}
		log.Printf("[ADMIN] force release spot %d", id)
		w.Write([]byte("Force release requested"))
	})))

	// ── СТАРЫЙ web-frontend (статика) ────────────────────────────────
	mux.Handle("/frontend/", http.StripPrefix("/frontend/", http.FileServer(http.Dir("./frontend"))))

	// ── CORS + старт ─────────────────────────────────────────────────
	c := cors.New(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"*"},
		AllowCredentials: true,
	})

	log.Println("🚀 Server started on :8080")
	log.Fatal(http.ListenAndServe(":8080", c.Handler(mux)))
}
