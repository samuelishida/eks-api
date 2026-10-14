package internal

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// schemaDDL is idempotent: CREATE TABLE IF NOT EXISTS is atomic in
// PostgreSQL, so concurrent replicas booting at the same time are safe
// (exactly one wins the CREATE; the rest are no-ops).
const schemaDDL = `CREATE TABLE IF NOT EXISTS items (
	id         BIGSERIAL PRIMARY KEY,
	name       TEXT NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
)`

// DB wraps the pgx pool plus the idempotent schema bootstrap.
type DB struct {
	pool *pgxpool.Pool
}

// New builds the pool, pings the database, and runs the idempotent
// schema bootstrap. It is the readiness gate: until New returns, the
// replica must not serve traffic.
func New(ctx context.Context, cfg Config) (*DB, error) {
	poolCfg, err := pgxpool.ParseConfig(cfg.DSN())
	if err != nil {
		return nil, fmt.Errorf("db: parse config: %w", err)
	}
	poolCfg.MaxConns = 10
	poolCfg.MaxConnLifetime = time.Hour

	pool, err := pgxpool.NewWithConfig(ctx, poolCfg)
	if err != nil {
		return nil, fmt.Errorf("db: create pool: %w", err)
	}

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("db: ping: %w", err)
	}

	if _, err := pool.Exec(ctx, schemaDDL); err != nil {
		pool.Close()
		return nil, fmt.Errorf("db: bootstrap schema: %w", err)
	}

	return &DB{pool: pool}, nil
}

// Ping reports database reachability. Used by /readyz.
func (d *DB) Ping(ctx context.Context) error {
	return d.pool.Ping(ctx)
}

// Close releases the pool.
func (d *DB) Close() {
	d.pool.Close()
}

// --- Item store (used by handlers and unit tests) ---

// Item is a row in the items table.
type Item struct {
	ID        int64     `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
}

// ItemStore is the database surface the handlers depend on. The real
// implementation is *DB; tests use a stub.
type ItemStore interface {
	Ping(ctx context.Context) error
	ListItems(ctx context.Context) ([]Item, error)
	InsertItem(ctx context.Context, name string) (Item, error)
	GetItem(ctx context.Context, id int64) (Item, error)
	UpdateItem(ctx context.Context, id int64, name string) (Item, error)
	DeleteItem(ctx context.Context, id int64) error
}

var _ ItemStore = (*DB)(nil)

func (d *DB) ListItems(ctx context.Context) ([]Item, error) {
	rows, err := d.pool.Query(ctx, `SELECT id, name, created_at FROM items ORDER BY id`)
	if err != nil {
		return nil, fmt.Errorf("db: list items: %w", err)
	}
	defer rows.Close()

	items := make([]Item, 0)
	for rows.Next() {
		var it Item
		if err := rows.Scan(&it.ID, &it.Name, &it.CreatedAt); err != nil {
			return nil, fmt.Errorf("db: scan item: %w", err)
		}
		items = append(items, it)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("db: list items: %w", err)
	}
	return items, nil
}

func (d *DB) InsertItem(ctx context.Context, name string) (Item, error) {
	var it Item
	err := d.pool.QueryRow(ctx,
		`INSERT INTO items (name) VALUES ($1) RETURNING id, name, created_at`, name,
	).Scan(&it.ID, &it.Name, &it.CreatedAt)
	if err != nil {
		return Item{}, fmt.Errorf("db: insert item: %w", err)
	}
	return it, nil
}

func (d *DB) GetItem(ctx context.Context, id int64) (Item, error) {
	var it Item
	err := d.pool.QueryRow(ctx,
		`SELECT id, name, created_at FROM items WHERE id = $1`, id,
	).Scan(&it.ID, &it.Name, &it.CreatedAt)
	if err != nil {
		return Item{}, fmt.Errorf("db: get item: %w", err)
	}
	return it, nil
}

func (d *DB) UpdateItem(ctx context.Context, id int64, name string) (Item, error) {
	var it Item
	err := d.pool.QueryRow(ctx,
		`UPDATE items SET name = $1 WHERE id = $2 RETURNING id, name, created_at`, name, id,
	).Scan(&it.ID, &it.Name, &it.CreatedAt)
	if err != nil {
		return Item{}, fmt.Errorf("db: update item: %w", err)
	}
	return it, nil
}

func (d *DB) DeleteItem(ctx context.Context, id int64) error {
	tag, err := d.pool.Exec(ctx, `DELETE FROM items WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("db: delete item: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// ErrNotFound is returned when a row does not exist.
var ErrNotFound = errors.New("not found")
