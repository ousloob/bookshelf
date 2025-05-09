package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"syscall"
	"time"

	"github.com/ardanlabs/conf/v3"
	"github.com/lmittmann/tint"
	"github.com/ousloob/bookshelf/api/inventory/routing"
	"github.com/ousloob/bookshelf/business/sys/database"
)

var build = "develop"

func main() {
	logger := slog.New(tint.NewHandler(os.Stderr, &tint.Options{
		AddSource:  true,
		Level:      slog.LevelDebug,
		TimeFormat: time.DateTime,
	})).With("API", "SALES")

	ctx := context.Background()
	if err := run(ctx, logger); err != nil {
		logger.ErrorContext(ctx, "startup", "msg", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, log *slog.Logger) error {

	// =========================================================================
	// GOMAXPROCS

	log.InfoContext(ctx, "startup", "GOMAXPROCS", runtime.GOMAXPROCS(0))

	// =========================================================================
	// Configuration

	cfg := struct {
		conf.Version
		Web struct {
			ReadTimeout     time.Duration `conf:"default:5s"`
			WriteTimeOut    time.Duration `conf:"default:10s"`
			IdleTimeout     time.Duration `conf:"default:12s"`
			ShutdownTimeout time.Duration `conf:"default:20s"`
			APIHost         string        `conf:"default:0.0.0.0:3000"`
		}
		DB struct {
			User         string `conf:"default:oussama"`
			Password     string `conf:"default:postgres"`
			Host         string `conf:"default:localhost"`
			Name         string `conf:"default:bookdb"`
			MaxIdleConns int    `conf:"default:0"`
			MaxOpenConns int    `conf:"default:0"`
			DisableTLS   bool   `conf:"default:true"`
		}
	}{
		Version: conf.Version{
			Build: build,
			Desc:  "© 2021 Oussama Moulana",
		},
	}

	// =========================================================================
	// App Starting

	log.InfoContext(ctx, "starting service", "environment", cfg.Build)
	defer log.InfoContext(ctx, "shutdown complete")

	if _, err := conf.Parse(cfg.Build, &cfg); err != nil {
		return fmt.Errorf("parse conf: %w", err)
	}

	log.InfoContext(ctx, "startup", "config", cfg)

	// =========================================================================
	// Database Support

	log.InfoContext(ctx, "startup", "status", "initalizing database support", "hostport", cfg.DB.Host)

	db, err := database.Open(database.Config{
		User:         cfg.DB.User,
		Password:     cfg.DB.Password,
		Host:         cfg.DB.Host,
		Name:         cfg.DB.Name,
		MaxIdleConns: cfg.DB.MaxIdleConns,
		MaxOpenConns: cfg.DB.MaxOpenConns,
		DisableTLS:   cfg.DB.DisableTLS,
	})
	if err != nil {
		return fmt.Errorf("connect to do db: %w", err)
	}

	defer func() {
		db.Close()
	}()

	// =========================================================================
	// Start API Service

	log.InfoContext(ctx, "startup", "status", "initializing V1 API support")

	// Make a channel to listen for an interrupt or terminal signal from the OS.
	// Use a buffered channel because the signal package require it.
	shutdown := make(chan os.Signal, 1)
	signal.Notify(shutdown, syscall.SIGINT, syscall.SIGTERM)

	// Construct the mux for the API calls.
	apiMux := routing.APIMux(
		routing.Bus{
			Shutdown: shutdown,
		},
	)

	// Construct a server to service the request against the mux.
	api := http.Server{
		Addr:         cfg.Web.APIHost,
		Handler:      apiMux,
		ReadTimeout:  cfg.Web.ReadTimeout,
		WriteTimeout: cfg.Web.WriteTimeOut,
		IdleTimeout:  cfg.Web.IdleTimeout,
		ErrorLog:     slog.NewLogLogger(log.Handler(), slog.LevelError),
	}

	// Make a channel to listen for errors coming from the listener. Use a
	// buffered channel so the goroutine can exit if we don't collect this
	// error.

	serveErrors := make(chan error, 1)

	// Start the service listening for api requests.
	go func() {
		log.InfoContext(ctx, "startup", "status", "api router started", "host", api.Addr)
		serveErrors <- api.ListenAndServe()
	}()

	// =========================================================================
	// Shutdown

	// Blocking main and waiting for shutdown
	select {
	case err := <-serveErrors:
		return fmt.Errorf("server error: %w", err)

	case sig := <-shutdown:
		log.InfoContext(ctx, "shutdown", "status", "shutdown started", "signal", sig)
		defer log.InfoContext(ctx, "shutdown", "status", "shutdown complete", "signal", sig)

		// give outstanding requests a deadline for completion.
		ctx, cancel := context.WithTimeout(context.Background(), cfg.Web.ShutdownTimeout)
		defer cancel()

		// Asking listener to shut down and shed load.
		if err := api.Shutdown(ctx); err != nil {
			api.Close()
			return fmt.Errorf("could not stop server gracefully: %w", err)
		}
	}

	return nil
}
