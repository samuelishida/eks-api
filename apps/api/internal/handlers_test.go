package internal

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
)

// stubStore is an in-memory ItemStore for unit tests (no live Postgres).
type stubStore struct {
	pingErr error
	items   map[int64]Item
	nextID  int64
}

func newStubStore() *stubStore {
	return &stubStore{items: map[int64]Item{}, nextID: 1}
}

func (s *stubStore) Ping(ctx context.Context) error { return s.pingErr }

func (s *stubStore) ListItems(ctx context.Context) ([]Item, error) {
	items := make([]Item, 0, len(s.items))
	for _, it := range s.items {
		items = append(items, it)
	}
	return items, nil
}

func (s *stubStore) InsertItem(ctx context.Context, name string) (Item, error) {
	it := Item{ID: s.nextID, Name: name, CreatedAt: time.Unix(0, 0)}
	s.nextID++
	s.items[it.ID] = it
	return it, nil
}

func (s *stubStore) GetItem(ctx context.Context, id int64) (Item, error) {
	it, ok := s.items[id]
	if !ok {
		return Item{}, ErrNotFound
	}
	return it, nil
}

func (s *stubStore) UpdateItem(ctx context.Context, id int64, name string) (Item, error) {
	it, ok := s.items[id]
	if !ok {
		return Item{}, ErrNotFound
	}
	it.Name = name
	s.items[id] = it
	return it, nil
}

func (s *stubStore) DeleteItem(ctx context.Context, id int64) error {
	if _, ok := s.items[id]; !ok {
		return ErrNotFound
	}
	delete(s.items, id)
	return nil
}

func newTestRouter(store ItemStore) *chi.Mux {
	r := chi.NewRouter()
	NewHandlers(store).Routes(r)
	return r
}

func TestHandlers(t *testing.T) {
	t.Run("healthz is 200 even when the DB is down", func(t *testing.T) {
		store := newStubStore()
		store.pingErr = errors.New("db down")
		r := newTestRouter(store)

		req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("healthz: got %d, want 200", rec.Code)
		}
	})

	t.Run("readyz is 200 when ping ok", func(t *testing.T) {
		store := newStubStore()
		r := newTestRouter(store)

		req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("readyz: got %d, want 200", rec.Code)
		}
	})

	t.Run("readyz is 503 when ping fails", func(t *testing.T) {
		store := newStubStore()
		store.pingErr = errors.New("connection refused")
		r := newTestRouter(store)

		req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, req)

		if rec.Code != http.StatusServiceUnavailable {
			t.Fatalf("readyz: got %d, want 503", rec.Code)
		}
	})

	t.Run("CRUD happy path", func(t *testing.T) {
		store := newStubStore()
		r := newTestRouter(store)

		// POST /api/v1/items -> 201
		req := httptest.NewRequest(http.MethodPost, "/api/v1/items", strings.NewReader(`{"name":"alpha"}`))
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		if rec.Code != http.StatusCreated {
			t.Fatalf("create: got %d, want 201 (body %s)", rec.Code, rec.Body.String())
		}
		var created Item
		if err := json.NewDecoder(rec.Body).Decode(&created); err != nil {
			t.Fatalf("create: decode: %v", err)
		}
		if created.ID != 1 || created.Name != "alpha" {
			t.Fatalf("create: unexpected item %+v", created)
		}

		// GET /api/v1/items -> 200, one item
		req = httptest.NewRequest(http.MethodGet, "/api/v1/items", nil)
		rec = httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("list: got %d, want 200", rec.Code)
		}
		var items []Item
		if err := json.NewDecoder(rec.Body).Decode(&items); err != nil {
			t.Fatalf("list: decode: %v", err)
		}
		if len(items) != 1 || items[0].Name != "alpha" {
			t.Fatalf("list: unexpected items %+v", items)
		}

		// GET /api/v1/items/1 -> 200
		req = httptest.NewRequest(http.MethodGet, "/api/v1/items/1", nil)
		rec = httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("get: got %d, want 200", rec.Code)
		}

		// PUT /api/v1/items/1 -> 200, name updated
		req = httptest.NewRequest(http.MethodPut, "/api/v1/items/1", strings.NewReader(`{"name":"beta"}`))
		rec = httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("update: got %d, want 200", rec.Code)
		}
		var updated Item
		if err := json.NewDecoder(rec.Body).Decode(&updated); err != nil {
			t.Fatalf("update: decode: %v", err)
		}
		if updated.Name != "beta" {
			t.Fatalf("update: unexpected item %+v", updated)
		}

		// DELETE /api/v1/items/1 -> 204
		req = httptest.NewRequest(http.MethodDelete, "/api/v1/items/1", nil)
		rec = httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		if rec.Code != http.StatusNoContent {
			t.Fatalf("delete: got %d, want 204", rec.Code)
		}

		// GET /api/v1/items/1 -> 404 after delete
		req = httptest.NewRequest(http.MethodGet, "/api/v1/items/1", nil)
		rec = httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("get after delete: got %d, want 404", rec.Code)
		}
	})

	t.Run("CRUD 404s", func(t *testing.T) {
		store := newStubStore()
		r := newTestRouter(store)

		for _, tc := range []struct {
			method string
			path   string
			body   string
		}{
			{http.MethodGet, "/api/v1/items/999", ""},
			{http.MethodPut, "/api/v1/items/999", `{"name":"x"}`},
			{http.MethodDelete, "/api/v1/items/999", ""},
		} {
			req := httptest.NewRequest(tc.method, tc.path, strings.NewReader(tc.body))
			rec := httptest.NewRecorder()
			r.ServeHTTP(rec, req)
			if rec.Code != http.StatusNotFound {
				t.Fatalf("%s %s: got %d, want 404", tc.method, tc.path, rec.Code)
			}
		}
	})

	t.Run("CRUD 400s", func(t *testing.T) {
		store := newStubStore()
		r := newTestRouter(store)

		cases := []struct {
			method string
			path   string
			body   string
		}{
			{http.MethodPost, "/api/v1/items", `not-json`},
			{http.MethodPost, "/api/v1/items", `{"name":""}`},
			{http.MethodPost, "/api/v1/items", `{}`},
			{http.MethodPut, "/api/v1/items/1", `not-json`},
			{http.MethodPut, "/api/v1/items/1", `{"name":""}`},
			{http.MethodGet, "/api/v1/items/notanumber", ""},
			{http.MethodGet, "/api/v1/items/0", ""},
		}
		for _, tc := range cases {
			req := httptest.NewRequest(tc.method, tc.path, strings.NewReader(tc.body))
			rec := httptest.NewRecorder()
			r.ServeHTTP(rec, req)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("%s %s (body %q): got %d, want 400", tc.method, tc.path, tc.body, rec.Code)
			}
		}
	})
}
