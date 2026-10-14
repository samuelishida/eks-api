package internal

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"strconv"
	"strings"
)

// Config holds the runtime configuration for the API.
type Config struct {
	HTTPAddr   string
	DBHost     string
	DBPort     int
	DBUser     string
	DBPassword string
	DBName     string
}

// String is safe for logging: the password is never included.
func (c Config) String() string {
	return fmt.Sprintf("HTTPAddr=%s DBHost=%s DBPort=%d DBUser=%s DBName=%s DBPassword=***",
		c.HTTPAddr, c.DBHost, c.DBPort, c.DBUser, c.DBName)
}

// DSN returns the Postgres connection string. Callers must not log it.
func (c Config) DSN() string {
	return "postgres://" + url.UserPassword(c.DBUser, c.DBPassword).String() +
		"@" + net.JoinHostPort(c.DBHost, strconv.Itoa(c.DBPort)) +
		"/" + c.DBName + "?sslmode=disable"
}

// Load reads configuration from the environment. Discrete DB_* variables
// take precedence over DATABASE_URL, which is used as a fallback base.
func Load() (Config, error) {
	var cfg Config

	if raw := os.Getenv("DATABASE_URL"); raw != "" {
		u, err := url.Parse(raw)
		if err != nil {
			return Config{}, fmt.Errorf("config: parse DATABASE_URL: %w", err)
		}
		if u.Scheme != "postgres" && u.Scheme != "postgresql" {
			return Config{}, fmt.Errorf("config: DATABASE_URL scheme %q is not postgres/postgresql", u.Scheme)
		}
		host, port, err := net.SplitHostPort(u.Host)
		if err != nil && u.Host != "" {
			return Config{}, fmt.Errorf("config: DATABASE_URL host %q: %w", u.Host, err)
		}
		cfg.DBHost = host
		if port == "" {
			port = "5432" // Postgres default when the URL omits the port
		}
		cfg.DBPort, err = strconv.Atoi(port)
		if err != nil {
			return Config{}, fmt.Errorf("config: DATABASE_URL port %q: %w", port, err)
		}
		cfg.DBName = strings.TrimPrefix(u.Path, "/")
		if u.User != nil {
			cfg.DBUser = u.User.Username()
			if pw, ok := u.User.Password(); ok {
				cfg.DBPassword = pw
			}
		}
	}

	cfg.DBHost = envOr("DB_HOST", cfg.DBHost)
	if p := os.Getenv("DB_PORT"); p != "" {
		v, err := strconv.Atoi(p)
		if err != nil {
			return Config{}, fmt.Errorf("config: DB_PORT: %w", err)
		}
		cfg.DBPort = v
	} else if cfg.DBPort == 0 {
		cfg.DBPort = 5432
	}
	cfg.DBUser = envOr("DB_USER", cfg.DBUser)
	cfg.DBPassword = envOr("DB_PASSWORD", cfg.DBPassword)
	cfg.DBName = envOr("DB_NAME", cfg.DBName)
	cfg.HTTPAddr = envOr("HTTP_ADDR", ":8080")

	if cfg.DBHost == "" {
		return Config{}, errors.New("config: DB host is required (set DB_HOST or DATABASE_URL)")
	}
	if cfg.DBPort < 1 || cfg.DBPort > 65535 {
		return Config{}, fmt.Errorf("config: DB port %d out of range", cfg.DBPort)
	}
	if cfg.DBName == "" {
		return Config{}, errors.New("config: DB name is required (set DB_NAME or a database path in DATABASE_URL)")
	}
	return cfg, nil
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
