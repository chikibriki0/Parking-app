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
	"errors"
	"log"
	"net/http"
	"net/mail"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/rs/cors"
	"golang.org/x/crypto/bcrypt"

	httpSwagger "github.com/swaggo/http-swagger"

	_ "parking-service/docs"
	"parking-service/internal/config"
	"parking-service/internal/model"
	"parking-service/internal/repository"
	"parking-service/internal/service"
)

const minPasswordLen = 6

func main() {
	cfg := config.Load()
	service.InitJWT(cfg.JWTSecret, cfg.JWTTTL)

	db, err := repository.NewDB(cfg.DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	userRepo := repository.NewUserRepository(db)
	parkingRepo := repository.NewParkingRepository(db)
	parkingService := service.NewParkingService(parkingRepo, cfg.ParkingExpireAfter)

	// Periodic sweeper finishes sessions older than ExpireAfter,
	// surviving server restarts.
	parkingService.StartExpirationSweeper(15 * time.Second)

	spotIDs, err := parkingRepo.GetAllSpotIDs()
	if err != nil {
		log.Fatal(err)
	}
	manager := model.NewParkingManager(spotIDs)

	// Симуляция включается отдельным флагом, чтобы прод-окружение
	// не наполняло БД фейковыми событиями.
	if cfg.SimulationEnabled {
		log.Println("Simulation: ENABLED — resetting demo state")
		// Демо-сброс: убираем «висячие» сессии и зависшие OCCUPIED-места,
		// чтобы каждый перезапуск начинался с чистой картинки.
		if err := parkingRepo.ResetDemoState(); err != nil {
			log.Println("demo reset error:", err)
		}
		stopSim := make(chan struct{})
		go manager.SimulateTraffic(stopSim)
		// drain simulation events
		go func() {
			for event := range manager.Events {
				log.Printf("[SIM] type=%v spot=%d source=%q",
					event.Type, event.SpotID, event.Source)
				if err := parkingService.HandleEvent(event); err != nil {
					// Симуляция оптимистично пометила место в своём
					// in-memory state до отправки. Если БД отказала
					// (например, место уже занято пользователем),
					// откатываем локальное состояние, чтобы потом
					// симуляция не «освободила» эту бронь.
					manager.RollbackLocalState(event)
					log.Println("simulation event error:", err)
					continue
				}
				broadcastEvent(event)
			}
		}()
	} else {
		log.Println("Simulation: DISABLED")
	}

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
		req.Email = strings.TrimSpace(strings.ToLower(req.Email))
		if _, err := mail.ParseAddress(req.Email); err != nil {
			http.Error(w, "Invalid email format", http.StatusBadRequest)
			return
		}
		if len(req.Password) < minPasswordLen {
			http.Error(w, "Password must be at least 6 characters", http.StatusBadRequest)
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
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"id":    user.ID,
			"email": user.Email,
			"role":  user.Role,
		})
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
		req.Email = strings.TrimSpace(strings.ToLower(req.Email))
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

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
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
			http.Error(w, "invalid spot id", http.StatusBadRequest)
			return
		}
		userID := r.Context().Value(service.UserIDKey).(int)

		// duration принимаем как query-param ?duration=2h (формат time.Duration).
		// Поддерживаются: 30m, 1h, 2h, 4h, 8h, 24h и любые корректные значения.
		// Если не передан — используется дефолтный ExpireAfter сервиса.
		duration := time.Duration(0)
		if s := r.URL.Query().Get("duration"); s != "" {
			if d, perr := time.ParseDuration(s); perr == nil {
				duration = d
			}
		}
		// Защитные пределы.
		if duration > 24*time.Hour {
			duration = 24 * time.Hour
		}

		now := time.Now()
		event := model.Event{
			Type: model.ReserveEvent, SpotID: id,
			UserID:    &userID,
			Source:    model.SourceUser,
			Timestamp: now,
			Duration:  duration,
		}
		if err := parkingService.HandleEvent(event); err != nil {
			respondParkingError(w, err)
			return
		}
		broadcastEvent(event)

		// Считаем актуальный expires_at: если клиент передал duration —
		// используем его, иначе дефолтный.
		effectiveDur := duration
		if effectiveDur <= 0 {
			effectiveDur = cfg.ParkingExpireAfter
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"spot_id":    id,
			"start_time": now,
			"expires_at": now.Add(effectiveDur),
		})
	})))

	mux.Handle("/extend/", service.JWTMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		// /extend/{spotId}?duration=1h — spotId оставлен для симметрии с reserve/release,
		// фактически продлеваем активную сессию пользователя.
		_, err := strconv.Atoi(strings.TrimPrefix(r.URL.Path, "/extend/"))
		if err != nil {
			http.Error(w, "invalid spot id", http.StatusBadRequest)
			return
		}
		dur, err := time.ParseDuration(r.URL.Query().Get("duration"))
		if err != nil || dur <= 0 {
			http.Error(w, "invalid duration", http.StatusBadRequest)
			return
		}
		if dur > 24*time.Hour {
			dur = 24 * time.Hour
		}
		userID := r.Context().Value(service.UserIDKey).(int)
		newExpires, err := parkingService.ExtendUserParking(userID, dur)
		if err != nil {
			switch {
			case errors.Is(err, service.ErrNoActiveParking):
				http.Error(w, "no active parking", http.StatusNotFound)
			case errors.Is(err, service.ErrExtensionTooLong):
				http.Error(w, "extension exceeds maximum total duration", http.StatusConflict)
			default:
				log.Println("extend error:", err)
				http.Error(w, "server error", http.StatusInternalServerError)
			}
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"expires_at": newExpires,
		})
	})))

	mux.Handle("/release/", service.JWTMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		id, err := strconv.Atoi(strings.TrimPrefix(r.URL.Path, "/release/"))
		if err != nil {
			http.Error(w, "invalid spot id", http.StatusBadRequest)
			return
		}
		userID := r.Context().Value(service.UserIDKey).(int)
		event := model.Event{
			Type: model.ReleaseEvent, SpotID: id,
			UserID: &userID, Source: model.SourceUser, Timestamp: time.Now(),
		}
		if err := parkingService.HandleEvent(event); err != nil {
			respondParkingError(w, err)
			return
		}
		broadcastEvent(event)
		w.Write([]byte(`{"ok":true}`))
	})))

	mux.Handle("/me", service.JWTMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		userID := r.Context().Value(service.UserIDKey).(int)
		user, err := userRepo.FindByID(userID)
		if err != nil || user == nil {
			http.Error(w, "user not found", http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"id":         user.ID,
			"email":      user.Email,
			"role":       user.Role,
			"created_at": user.CreatedAt,
		})
	})))

	mux.Handle("/my/parking", service.JWTMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		userID := r.Context().Value(service.UserIDKey).(int)
		spotID, startTime, expiresAt, err := parkingService.GetActiveParking(userID)
		if err != nil {
			if errors.Is(err, service.ErrNoActiveParking) {
				http.Error(w, "No active parking", http.StatusNotFound)
				return
			}
			http.Error(w, "server error", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		var expiresField interface{}
		if !expiresAt.IsZero() {
			expiresField = expiresAt
		}
		json.NewEncoder(w).Encode(map[string]interface{}{
			"expires_at": expiresField,
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
		event := model.Event{
			Type: model.ReleaseEvent, SpotID: id,
			Source: "ADMIN", Timestamp: time.Now(),
		}
		if err := parkingService.HandleEvent(event); err != nil {
			respondParkingError(w, err)
			return
		}
		broadcastEvent(event)
		log.Printf("[ADMIN] force release spot %d", id)
		w.Write([]byte(`{"ok":true}`))
	})))

	mux.Handle("/frontend/", http.StripPrefix("/frontend/", http.FileServer(http.Dir("./frontend"))))

	c := cors.New(cors.Options{
		AllowedOrigins:   cfg.CORSAllowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Authorization", "Content-Type"},
		AllowCredentials: !contains(cfg.CORSAllowedOrigins, "*"),
	})

	// Final middleware chain: CORS → request logging → mux
	handler := loggingMiddleware(c.Handler(mux))

	server := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
	}

	// Graceful shutdown: ловим SIGINT/SIGTERM (Ctrl+C, docker stop).
	ctx, stop := signal.NotifyContext(context.Background(),
		syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		log.Printf("Server started on %s", cfg.HTTPAddr)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("listen error: %v", err)
		}
	}()

	<-ctx.Done()
	log.Println("Shutdown signal received, draining...")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Printf("graceful shutdown error: %v", err)
	} else {
		log.Println("HTTP server stopped")
	}
}

// loggingMiddleware пишет в лог метод, путь, статус и время выполнения
// каждого запроса — полезно для отладки на демо и для метрики качества кода.
func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: 200}
		next.ServeHTTP(rec, r)
		log.Printf("%s %s -> %d (%s)",
			r.Method, r.URL.Path, rec.status, time.Since(start).Round(time.Millisecond))
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

func respondParkingError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, service.ErrSpotNotFound):
		http.Error(w, err.Error(), http.StatusNotFound)
	case errors.Is(err, service.ErrSpotOccupied),
		errors.Is(err, service.ErrUserHasActiveParking):
		http.Error(w, err.Error(), http.StatusConflict)
	default:
		log.Println("parking error:", err)
		http.Error(w, "server error", http.StatusInternalServerError)
	}
}

func broadcastEvent(event model.Event) {
	data, _ := json.Marshal(map[string]interface{}{
		"spot_id": event.SpotID,
		"type":    event.Type,
		"source":  event.Source,
	})
	service.Broadcast(data)
}

func contains(ss []string, s string) bool {
	for _, x := range ss {
		if x == s {
			return true
		}
	}
	return false
}
