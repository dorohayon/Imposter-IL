package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/api"
	"github.com/dorohayon/Imposter-IL/server/internal/content"
)

func TestHealthz(t *testing.T) {
	rec := httptest.NewRecorder()
	newMux().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK || rec.Body.String() != `{"status":"ok"}` {
		t.Fatalf("got %d %q", rec.Code, rec.Body.String())
	}
	rec = httptest.NewRecorder()
	newMux().ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/healthz", nil))
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("POST got %d", rec.Code)
	}
}

// readyz must keep answering while draining, and say it is not ready, so the
// load balancer stops adding players without the instance being killed.
func TestReadyzReportsDraining(t *testing.T) {
	srv := api.NewServer(time.Now, content.Policy(), content.Pick)
	mux := newMuxFor(srv)

	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("before draining: %d %q", rec.Code, rec.Body.String())
	}

	srv.Drain()
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("while draining: %d %q", rec.Code, rec.Body.String())
	}

	// Liveness is unchanged: the process must not be killed while it drains.
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("healthz while draining: %d", rec.Code)
	}
}
