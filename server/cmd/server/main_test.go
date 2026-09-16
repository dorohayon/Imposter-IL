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

// Cloud Run has no shell, so the loopback metrics listener is unreachable
// there and the counters have to come over the public port — but only to
// someone holding the token.
func TestMetricsTokenGate(t *testing.T) {
	t.Setenv("METRICS_TOKEN", "s3cret")
	mux := newMuxFor(api.NewServer(time.Now, content.Policy(), content.Pick))

	for _, tc := range []struct {
		name, header string
		want         int
	}{
		{"no header", "", http.StatusNotFound},
		{"wrong token", "Bearer nope", http.StatusNotFound},
		{"right token", "Bearer s3cret", http.StatusOK},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
			if tc.header != "" {
				req.Header.Set("Authorization", tc.header)
			}
			rec := httptest.NewRecorder()
			mux.ServeHTTP(rec, req)
			if rec.Code != tc.want {
				t.Fatalf("got %d, want %d", rec.Code, tc.want)
			}
		})
	}
}

// Without the token there is no public /metrics at all.
func TestMetricsNotPublicByDefault(t *testing.T) {
	rec := httptest.NewRecorder()
	newMux().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("got %d, want 404", rec.Code)
	}
}
