package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/eks-api/apps/api/internal"
)

func main() {
	// Config is validated up front: on an invalid config, log and exit
	// non-zero (the container should crash-loop, not serve broken).
	cfg, err := internal.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	log.Printf("api: starting (%s)", cfg)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	// Readiness gate: build the pool, ping, and run the idempotent schema
	// bootstrap before the server accepts traffic. Liveness (/healthz)
	// does not depend on this — it only reports the process is up.
	db, err := internal.New(ctx, cfg)
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	defer db.Close()

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	internal.NewHandlers(db).Routes(r)

	srv := &http.Server{
		Addr:         cfg.HTTPAddr,
		Handler:      r,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("api: listening on %s", cfg.HTTPAddr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("http: %v", err)
		}
	}()

	// Graceful shutdown: stop accepting new connections, drain in-flight
	// requests, then close the DB pool via defer.
	<-ctx.Done()
	log.Printf("api: shutdown signal received")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("api: graceful shutdown: %v", err)
	}
	log.Printf("api: stopped")
}
