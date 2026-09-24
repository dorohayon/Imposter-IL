// Package legal sends the addresses the game server used to publish the Terms
// of Use and Privacy Policy on to the public site, https://imposteril.github.io,
// which is built from site/ in this repository (docs/legal.md).
//
// Builds up to 3 link to the documents on whichever server they talk to, and
// store listings may still carry these URLs, so they keep answering: a
// permanent redirect rather than a second copy to keep in step.
package legal

import "net/http"

// Site is where the documents live now.
const Site = "https://imposteril.github.io"

// Routes registers the old addresses. They sit outside the API's gate on
// purpose: a browser sends no X-Client-Build header.
func Routes(mux *http.ServeMux) {
	for from, to := range map[string]string{
		"GET /privacy/": "/privacy/",
		"GET /terms/":   "/terms/",
		"GET /legal/":   "/",
	} {
		mux.HandleFunc(from, func(w http.ResponseWriter, r *http.Request) {
			http.Redirect(w, r, Site+to, http.StatusMovedPermanently)
		})
	}
}
