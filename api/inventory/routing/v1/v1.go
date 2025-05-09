// Package v1 contains the full set of handler functions and routes supported
// by the v1 web api.
package v1

import (
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
)

type Bus struct {
	Log *slog.Logger
}

// Routes binds all the version 1 routes.
func Routes(router *chi.Mux, bus Bus) {
	router.Get("/", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("Salam Alaikoum"))
	})
}
