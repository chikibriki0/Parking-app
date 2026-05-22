package service

import (
	"errors"
	"testing"
	"time"

	"parking-service/internal/model"
)

// mockRepo — ручной мок ParkingRepository для unit-тестов.
// Записывает все вызовы, чтобы тесты могли проверять и аргументы, и факт вызова.
type mockRepo struct {
	startErr           error
	endErr             error
	hasUserSession     bool
	hasUserSessionErr  error
	startCalls         []startCall
	endCalls           []endCall
	hasUserSessionGets []int
}

type startCall struct {
	userID   *int
	spotID   int
	start    time.Time
	duration time.Duration
	source   string
}

type endCall struct {
	spotID int
	end    time.Time
}

func (m *mockRepo) StartParking(userID *int, spotID int, start time.Time, duration time.Duration, source string) error {
	m.startCalls = append(m.startCalls, startCall{userID, spotID, start, duration, source})
	return m.startErr
}

func (m *mockRepo) EndParking(spotID int, end time.Time) error {
	m.endCalls = append(m.endCalls, endCall{spotID, end})
	return m.endErr
}

func (m *mockRepo) HasActiveUserSession(spotID int) (bool, error) {
	m.hasUserSessionGets = append(m.hasUserSessionGets, spotID)
	return m.hasUserSession, m.hasUserSessionErr
}

// Незадействованные в тестах методы — пустые заглушки для соответствия интерфейсу.
func (m *mockRepo) GetActiveParking(int) (int, time.Time, time.Time, error) {
	return 0, time.Time{}, time.Time{}, nil
}
func (m *mockRepo) ExtendUserParking(int, time.Duration, time.Duration) (time.Time, error) {
	return time.Time{}, nil
}
func (m *mockRepo) GetUserHistory(int) ([]map[string]interface{}, error) { return nil, nil }
func (m *mockRepo) GetStats() (int, int, int, error)                     { return 0, 0, 0, nil }
func (m *mockRepo) ExpireDueSessions(time.Time) ([]int, error)           { return nil, nil }
func (m *mockRepo) GetAllUsers() ([]map[string]interface{}, error)       { return nil, nil }
func (m *mockRepo) GetAllActiveSessions() ([]map[string]interface{}, error) {
	return nil, nil
}
func (m *mockRepo) GetAllParkingHistory() ([]map[string]interface{}, error) { return nil, nil }

// -------------------- Тесты --------------------

func TestHandleEvent_ReserveUsesDefaultExpireAfter(t *testing.T) {
	repo := &mockRepo{}
	svc := NewParkingService(repo, 2*time.Minute)

	userID := 42
	now := time.Date(2025, 1, 1, 10, 0, 0, 0, time.UTC)
	err := svc.HandleEvent(model.Event{
		Type:      model.ReserveEvent,
		SpotID:    5,
		UserID:    &userID,
		Timestamp: now,
		Source:    model.SourceUser,
		// Duration намеренно zero — должны использовать default.
	})

	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(repo.startCalls) != 1 {
		t.Fatalf("expected 1 StartParking call, got %d", len(repo.startCalls))
	}
	c := repo.startCalls[0]
	if c.duration != 2*time.Minute {
		t.Errorf("expected default duration 2m, got %v", c.duration)
	}
	if c.spotID != 5 {
		t.Errorf("expected spot id 5, got %d", c.spotID)
	}
	if c.source != model.SourceUser {
		t.Errorf("expected source USER, got %q", c.source)
	}
}

func TestHandleEvent_ReserveRespectsExplicitDuration(t *testing.T) {
	repo := &mockRepo{}
	svc := NewParkingService(repo, 2*time.Minute)

	err := svc.HandleEvent(model.Event{
		Type:     model.ReserveEvent,
		SpotID:   7,
		Duration: 4 * time.Hour,
		Source:   model.SourceUser,
	})

	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got := repo.startCalls[0].duration; got != 4*time.Hour {
		t.Errorf("expected 4h, got %v", got)
	}
}

func TestHandleEvent_ReservePropagatesTypedError(t *testing.T) {
	repo := &mockRepo{startErr: ErrSpotOccupied}
	svc := NewParkingService(repo, 2*time.Minute)

	err := svc.HandleEvent(model.Event{Type: model.ReserveEvent, SpotID: 1})

	if !errors.Is(err, ErrSpotOccupied) {
		t.Errorf("expected ErrSpotOccupied, got %v", err)
	}
}

func TestHandleEvent_SimulationReleaseSkipsUserSession(t *testing.T) {
	repo := &mockRepo{hasUserSession: true}
	svc := NewParkingService(repo, 2*time.Minute)

	err := svc.HandleEvent(model.Event{
		Type:   model.ReleaseEvent,
		SpotID: 3,
		Source: model.SourceSimulation,
	})

	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(repo.endCalls) != 0 {
		t.Fatalf("EndParking must NOT be called for simulation when a user session is active; got %d calls", len(repo.endCalls))
	}
	if len(repo.hasUserSessionGets) != 1 || repo.hasUserSessionGets[0] != 3 {
		t.Errorf("expected HasActiveUserSession(3), got %+v", repo.hasUserSessionGets)
	}
}

func TestHandleEvent_SimulationReleaseProceedsWhenNoUserSession(t *testing.T) {
	repo := &mockRepo{hasUserSession: false}
	svc := NewParkingService(repo, 2*time.Minute)

	err := svc.HandleEvent(model.Event{
		Type:   model.ReleaseEvent,
		SpotID: 4,
		Source: model.SourceSimulation,
	})

	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(repo.endCalls) != 1 || repo.endCalls[0].spotID != 4 {
		t.Fatalf("expected EndParking(4), got %+v", repo.endCalls)
	}
}

func TestHandleEvent_UserReleaseAlwaysCallsEndParking(t *testing.T) {
	// Даже если симуляционная защита сказала бы «не трогать», пользовательский
	// release должен пройти всегда.
	repo := &mockRepo{hasUserSession: true}
	svc := NewParkingService(repo, 2*time.Minute)

	err := svc.HandleEvent(model.Event{
		Type:   model.ReleaseEvent,
		SpotID: 9,
		Source: model.SourceUser,
	})

	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(repo.endCalls) != 1 || repo.endCalls[0].spotID != 9 {
		t.Fatalf("expected EndParking(9), got %+v", repo.endCalls)
	}
	if len(repo.hasUserSessionGets) != 0 {
		t.Error("HasActiveUserSession не должен вызываться для пользовательского release")
	}
}

func TestIsTypedClientError(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{"ErrSpotOccupied", ErrSpotOccupied, true},
		{"ErrSpotNotFound", ErrSpotNotFound, true},
		{"ErrUserHasActiveParking", ErrUserHasActiveParking, true},
		{"ErrNoActiveParking", ErrNoActiveParking, true},
		{"random error", errors.New("boom"), false},
		{"nil", nil, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isTypedClientError(tc.err); got != tc.want {
				t.Errorf("isTypedClientError(%v) = %v, want %v", tc.err, got, tc.want)
			}
		})
	}
}
