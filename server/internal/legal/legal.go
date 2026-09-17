// Package legal serves the public Terms of Use and Privacy Policy.
//
// The app stores require a publicly reachable privacy policy URL, and GitHub
// Pages cannot publish a private repository without a paid plan. The game
// server already has a public HTTPS hostname and certificate, so the documents
// ride on it: no second host to pay for, to deploy, or to leave behind when
// the documents change.
package legal

import (
	"embed"
	"io/fs"
	"net/http"
)

//go:embed site
var site embed.FS

// Routes serves the documents. The store listings link /privacy and /terms;
// /legal is the landing page that links to both. A request without the
// trailing slash is redirected to it by the mux.
//
// They are registered outside the API's gate on purpose: a browser sends no
// X-Client-Build header, and a store reviewer reading the policy is not a
// player to rate-limit.
func Routes(mux *http.ServeMux) {
	pages, err := fs.Sub(site, "site")
	if err != nil {
		panic(err) // The files are embedded, so this cannot fail at runtime.
	}
	files := http.FileServerFS(pages)
	mux.Handle("GET /privacy/", files)
	mux.Handle("GET /terms/", files)
	mux.Handle("GET /style.css", files)
	mux.Handle("GET /legal/", http.StripPrefix("/legal", files))
}
