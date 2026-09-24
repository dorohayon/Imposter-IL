package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
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

// The documents moved to the public site (docs/legal.md). Old builds and
// store listings still carry the server's addresses, so a browser — which
// sends no X-Client-Build header — must be sent on, not refused.
func TestLegalPagesRedirectToTheSite(t *testing.T) {
	srv := api.NewServer(time.Now, content.Policy(), content.Pick)
	srv.RequireClientBuild(999)
	mux := newMuxFor(srv)

	for path, want := range map[string]string{
		"/privacy/": "https://imposteril.github.io/privacy/",
		"/terms/":   "https://imposteril.github.io/terms/",
		"/legal/":   "https://imposteril.github.io/",
		// Without the trailing slash the mux redirects first; it still lands.
		"/privacy": "/privacy/",
	} {
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code/100 != 3 || rec.Header().Get("Location") != want {
			t.Errorf("GET %s = %d %q, want a redirect to %s", path, rec.Code, rec.Header().Get("Location"), want)
		}
	}
}

// A shared room link has to open for a friend with a browser and no app, so it
// sits outside the version gate like the legal pages.
func TestInvitePageIsServed(t *testing.T) {
	srv := api.NewServer(time.Now, content.Policy(), content.Pick)
	srv.RequireClientBuild(999)
	mux := newMuxFor(srv)

	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/join/123456", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /join/123456 = %d, want 200", rec.Code)
	}
	body := rec.Body.String()
	if !strings.Contains(body, ">123456<") {
		t.Error("the page does not show the room code")
	}
	if !strings.Contains(body, "imposteril://join/123456") {
		t.Error("the page does not hand the code to the app")
	}

	// Anything that is not a room code is not a room.
	for _, code := range []string{"12345", "1234567", "abcdef", "12345a"} {
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/join/"+code, nil))
		if rec.Code != http.StatusNotFound {
			t.Errorf("GET /join/%s = %d, want 404", code, rec.Code)
		}
	}
}

func TestMonetizationFromEnv(t *testing.T) {
	t.Setenv("MONETIZATION_CONFIG", "")
	t.Setenv("APPLE_BUNDLE_ID", "")
	t.Setenv("GOOGLE_PLAY_PACKAGE", "")
	cfg, verifiers, err := monetizationFromEnv()
	if err != nil || len(verifiers) != 0 || cfg.ServerEnforcement {
		t.Fatalf("defaults: %+v %v %v", cfg, verifiers, err)
	}

	t.Setenv("MONETIZATION_CONFIG", `{"freeCategoryIds":["sports"],"serverEnforcement":true}`)
	t.Setenv("APPLE_BUNDLE_ID", "com.imposter.il")
	cfg, verifiers, err = monetizationFromEnv()
	if err != nil || !cfg.ServerEnforcement || cfg.FreeCategoryIDs[0] != "sports" || verifiers["ios"] == nil {
		t.Fatalf("override: %+v %v %v", cfg, verifiers, err)
	}

	// A config or key that does not parse must stop the server, not fall
	// back to defaults and quietly change what players pay for.
	t.Setenv("MONETIZATION_CONFIG", `{"freeCategoryIds":["cars"]}`)
	if _, _, err := monetizationFromEnv(); err == nil {
		t.Fatal("invalid config accepted")
	}
	t.Setenv("MONETIZATION_CONFIG", "")
	t.Setenv("GOOGLE_PLAY_PACKAGE", "com.imposter.il")
	t.Setenv("GOOGLE_PLAY_SERVICE_ACCOUNT", "{}")
	if _, _, err := monetizationFromEnv(); err == nil {
		t.Fatal("broken service account accepted")
	}
}
