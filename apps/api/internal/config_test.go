package internal

import (
	"net/url"
	"testing"
)

func clearConfigEnv(t *testing.T) {
	t.Helper()
	for _, key := range []string{"DATABASE_URL", "DB_HOST", "DB_PORT", "DB_USER", "DB_PASSWORD", "DB_NAME", "DB_SSLMODE", "HTTP_ADDR"} {
		t.Setenv(key, "")
	}
}

func TestLoadDatabaseURLWithoutPortDefaultsToPostgresPort(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("DATABASE_URL", "postgres://api:p%40ss@db.example.com/app?sslmode=verify-full")

	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.DBHost != "db.example.com" || cfg.DBPort != 5432 {
		t.Fatalf("got DB host/port %q:%d, want db.example.com:5432", cfg.DBHost, cfg.DBPort)
	}
	if cfg.DBUser != "api" || cfg.DBPassword != "p@ss" || cfg.DBName != "app" {
		t.Fatalf("database URL fields were not decoded: %+v", cfg)
	}
	if cfg.DBSSLMode != "verify-full" {
		t.Fatalf("got sslmode %q, want verify-full", cfg.DBSSLMode)
	}

	dsn, err := url.Parse(cfg.DSN())
	if err != nil {
		t.Fatal(err)
	}
	if dsn.Query().Get("sslmode") != "verify-full" {
		t.Fatalf("DSN dropped URL sslmode: %q", cfg.DSN())
	}
	if password, ok := dsn.User.Password(); !ok || password != "p@ss" {
		t.Fatalf("DSN did not encode password safely: %q", cfg.DSN())
	}
}

func TestLoadDefaultsToEncryptedDatabaseConnections(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("DB_HOST", "localhost")
	t.Setenv("DB_NAME", "app")

	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.DBSSLMode != "require" {
		t.Fatalf("got sslmode %q, want require", cfg.DBSSLMode)
	}
}

func TestLoadRejectsInvalidSSLMode(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("DB_HOST", "localhost")
	t.Setenv("DB_NAME", "app")
	t.Setenv("DB_SSLMODE", "plain")

	if _, err := Load(); err == nil {
		t.Fatal("Load accepted invalid DB_SSLMODE")
	}
}
