package config

import (
	"testing"
	"time"
)

func TestGetEnvFallback(t *testing.T) {
	t.Setenv("X_DOES_NOT_EXIST", "")
	// если значение отсутствует, должен вернуться fallback
	if got := getEnv("X_NOT_SET_AT_ALL_42", "fallback"); got != "fallback" {
		t.Errorf("expected fallback, got %q", got)
	}
	t.Setenv("X_SET", "value")
	if got := getEnv("X_SET", "fallback"); got != "value" {
		t.Errorf("expected value, got %q", got)
	}
}

func TestGetDuration_Valid(t *testing.T) {
	t.Setenv("X_DUR", "5m30s")
	if got := getDuration("X_DUR", time.Minute); got != 5*time.Minute+30*time.Second {
		t.Errorf("expected 5m30s, got %v", got)
	}
}

func TestGetDuration_InvalidUsesFallback(t *testing.T) {
	t.Setenv("X_DUR_BAD", "definitely-not-a-duration")
	if got := getDuration("X_DUR_BAD", 7*time.Minute); got != 7*time.Minute {
		t.Errorf("expected fallback 7m, got %v", got)
	}
}

func TestGetBool(t *testing.T) {
	t.Setenv("FLAG_TRUE", "true")
	t.Setenv("FLAG_FALSE", "false")
	t.Setenv("FLAG_BAD", "maybe")

	if !getBool("FLAG_TRUE", false) {
		t.Error("expected true")
	}
	if getBool("FLAG_FALSE", true) {
		t.Error("expected false")
	}
	// невалидное значение → fallback
	if !getBool("FLAG_BAD", true) {
		t.Error("expected fallback true for bad value")
	}
	if getBool("FLAG_UNSET_HOPEFULLY_42", false) {
		t.Error("expected fallback false for unset")
	}
}

func TestSplitCSV(t *testing.T) {
	cases := []struct {
		in   string
		want []string
	}{
		{"a,b,c", []string{"a", "b", "c"}},
		{" a , b , c ", []string{"a", "b", "c"}},
		{"", []string{}},
		{",,a,,", []string{"a"}},
		{"*", []string{"*"}},
	}
	for _, c := range cases {
		got := splitCSV(c.in)
		if !sliceEqual(got, c.want) {
			t.Errorf("splitCSV(%q) = %v, want %v", c.in, got, c.want)
		}
	}
}

func sliceEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
