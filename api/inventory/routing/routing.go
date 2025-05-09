// Package routing manages the API routing and middleware setup.
package routing

import (
	"log/slog"
	"os"

	"github.com/go-chi/chi/v5"
	v1 "github.com/ousloob/bookshelf/api/inventory/routing/v1"
	"github.com/ousloob/bookshelf/support/web/mid"
)

// Bus carries shared resources across the application.
type Bus struct {
	Log      *slog.Logger
	Shutdown chan os.Signal
}

// APIMux constructs and returns the API Router.
func APIMux(bus Bus) *chi.Mux {

	mux := chi.NewRouter()
	mux.Use(mid.Logger)

	v1.Routes(mux, v1.Bus{Log: bus.Log})

	return mux
}
