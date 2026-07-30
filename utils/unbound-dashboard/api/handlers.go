// Package api provides RESTful JSON endpoints.
package api

import (
	"encoding/json"
	"net/http"
	"time"

	"unbound-dashboard/core"
	"unbound-dashboard/database"
)

// Handler wraps the HTTP server components.
type Handler struct {
	db  *database.Database
	cfg *core.Config
}

// NewHandler creates a new API handler instance.
func NewHandler(db *database.Database, cfg *core.Config) *Handler {
	return &Handler{db: db, cfg: cfg}
}

// HandleStats returns dashboard statistics in JSON format.
func (h *Handler) HandleStats(w http.ResponseWriter, r *http.Request) {
	stats := h.db.GetStats()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"total_queries":    stats["TotalQueries"],
		"blocked_queries":  stats["BlockedQueries"],
		"uptime_seconds":   time.Since(startTime).Seconds(),
	})
}

var startTime = time.Now()

// GetRouter sets up the HTTP routes.
func (h *Handler) GetRouter() *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("/stats", h.HandleStats)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTeapot) // Placeholder: Not ready yet
	})

	return mux
}
