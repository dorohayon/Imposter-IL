package invite

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

// The page shows the same hero the app opens on, and the server cannot reach
// outside its own module to embed it, so there are two copies. This is what
// keeps them from drifting apart.
func TestHeroMatchesTheAppAsset(t *testing.T) {
	want, err := os.ReadFile("../../../assets/illustrations/home-hero.webp")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(hero, want) {
		t.Error("server/internal/invite/home-hero.webp differs from assets/illustrations/home-hero.webp")
	}
}

func TestPageCarriesTheInvitation(t *testing.T) {
	mux := http.NewServeMux()
	Routes(mux)

	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/join/123456", nil))
	body := rec.Body.String()
	for _, want := range []string{
		"הוזמנתם למשחק",
		"מי המתחזה?",
		"כולם יודעים את המילה. חוץ מאחד.",
		"/join/hero.webp",
		">123456<",
		"imposteril://join/123456",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("the page is missing %q", want)
		}
	}

	// The image sits under /join/, so it must not be read as a room code.
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/join/hero.webp", nil))
	if rec.Code != http.StatusOK || rec.Header().Get("Content-Type") != "image/webp" {
		t.Fatalf("hero = %d %q", rec.Code, rec.Header().Get("Content-Type"))
	}
	if !bytes.Equal(rec.Body.Bytes(), hero) {
		t.Error("the hero route served something else")
	}
}

// Android checks this file before it lets a /join/ link skip the page.
func TestAssetLinksNameTheApp(t *testing.T) {
	mux := http.NewServeMux()
	Routes(mux)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/.well-known/assetlinks.json", nil))
	var links []struct {
		Target struct {
			Package      string   `json:"package_name"`
			Fingerprints []string `json:"sha256_cert_fingerprints"`
		} `json:"target"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &links); err != nil {
		t.Fatalf("not JSON: %v", err)
	}
	if rec.Header().Get("Content-Type") != "application/json" || len(links) != 1 ||
		links[0].Target.Package != "com.imposteril.app" || len(links[0].Target.Fingerprints) == 0 {
		t.Errorf("assetlinks = %s", rec.Body)
	}
}
