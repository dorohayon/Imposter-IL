// Package invite serves the page a shared room link points at.
//
// A room code pasted into a chat is only a number; a link is something a
// friend can tap. The page carries the code and hands the phone to the app,
// and it lives on the game server because that is the address the app already
// talks to and already has a certificate for.
package invite

import (
	_ "embed"
	"io"
	"net/http"
	"strings"
)

//go:embed join.html
var page string

//go:embed home-hero.webp
var hero []byte

// assetLinks lets Android open /join/ links straight in the app (an App Link)
// instead of this page. Each entry is the SHA-256 of a certificate the app
// is signed with: the upload key, which signs the APKs installed by hand.
// ponytail: add Google Play's app signing key from Play Console (Setup → App
// signing) once the app is there, or store installs will still get the page.
const assetLinks = `[{"relation":["delegate_permission/common.handle_all_urls"],` +
	`"target":{"namespace":"android_app","package_name":"com.imposteril.app",` +
	`"sha256_cert_fingerprints":["ED:E1:F1:45:3C:1F:4A:9C:BF:F4:B5:E0:EF:6E:8B:66:A4:8A:F5:78:97:B4:A0:0B:AD:99:77:D4:09:13:BB:07"]}}]`

// CodeLength matches the room codes rooms actually get.
const CodeLength = 6

// Routes serves /join/{code} and the App Link declaration for it. It is registered outside the API's gate: the
// friend following the link has a browser, not a build number.
func Routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /.well-known/assetlinks.json", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, assetLinks)
	})
	mux.HandleFunc("GET /join/hero.webp", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "image/webp")
		w.Header().Set("Cache-Control", "public, max-age=86400")
		_, _ = w.Write(hero)
	})
	mux.HandleFunc("GET /join/{code}", func(w http.ResponseWriter, r *http.Request) {
		code := r.PathValue("code")
		if !validCode(code) {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// The code is six digits by the time it gets here, so there is nothing
		// left to escape.
		_, _ = io.WriteString(w, strings.ReplaceAll(page, "{{code}}", code))
	})
}

func validCode(code string) bool {
	if len(code) != CodeLength {
		return false
	}
	for _, r := range code {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}
