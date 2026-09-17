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

// CodeLength matches the room codes rooms actually get.
const CodeLength = 6

// Routes serves /join/{code}. It is registered outside the API's gate: the
// friend following the link has a browser, not a build number.
func Routes(mux *http.ServeMux) {
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
