// Command server runs the מי המתחזה? backend.
package main

import (
	"cmp"
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/api"
	"github.com/dorohayon/Imposter-IL/server/internal/content"
)

func main() {
	addr := ":" + cmp.Or(os.Getenv("PORT"), "8080")
	srv := &http.Server{Addr: addr, Handler: newMux(), ReadHeaderTimeout: 5 * time.Second}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		log.Printf("listening on %s", addr)
		if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
			log.Fatal(err)
		}
	}()
	<-ctx.Done()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("shutdown: %v", err)
	}
}

func newMux() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})
	api.NewServer(time.Now, content.Policy(), content.Pick).Routes(mux)
	return mux
}
