// Command server runs the מי המתחזה? backend.
package main

import (
	"cmp"
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/api"
	"github.com/dorohayon/Imposter-IL/server/internal/content"
)

// Environment:
//
//	PORT           listen port (default 8080)
//	METRICS_ADDR   private /metrics listener (default 127.0.0.1:9090, "" to disable)
//	TRUST_PROXY    "1" to read the client address from X-Forwarded-For
//	DRAIN_TIMEOUT  how long to let games finish on SIGTERM (default 10m)
//	MIN_CLIENT_BUILD  oldest app build served (default 0: every client)
//	LOG_LEVEL      debug | info | warn | error (default info)
func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: logLevel()})))

	srv := api.NewServer(time.Now, content.Policy(), content.Pick)
	srv.TrustProxy(os.Getenv("TRUST_PROXY") == "1")
	if build, err := strconv.Atoi(os.Getenv("MIN_CLIENT_BUILD")); err == nil && build > 0 {
		srv.RequireClientBuild(build)
		slog.Info("refusing older clients", "minClientBuild", build)
	}

	addr := ":" + cmp.Or(os.Getenv("PORT"), "8080")
	http1 := &http.Server{Addr: addr, Handler: newMuxFor(srv), ReadHeaderTimeout: 5 * time.Second}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go srv.Run(ctx) // reaper: idle sessions, empty rooms, spent rate-limit buckets
	go serveMetrics(ctx, srv)
	go func() {
		slog.Info("listening", "addr", addr)
		if err := http1.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
			slog.Error("listen", "err", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	drain(srv)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := http1.Shutdown(shutdownCtx); err != nil {
		slog.Error("shutdown", "err", err)
	}
	slog.Info("stopped")
}

// drain lets the games already in progress finish before the process exits.
// Game state lives only in memory, so without this every deploy ends every
// game in flight. /readyz reports not ready throughout, so the load balancer
// sends new players elsewhere.
func drain(srv *api.Server) {
	timeout := 10 * time.Minute
	if d, err := time.ParseDuration(os.Getenv("DRAIN_TIMEOUT")); err == nil && d > 0 {
		timeout = d
	}
	srv.Drain()

	deadline := time.Now().Add(timeout)
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		games := srv.ActiveGames()
		if games == 0 {
			slog.Info("drained, no games left")
			return
		}
		if !time.Now().Before(deadline) {
			slog.Warn("drain timed out, ending games in progress", "games", games)
			return
		}
		slog.Info("draining", "games", games, "secondsLeft", int(time.Until(deadline).Seconds()))
		<-ticker.C
	}
}

// serveMetrics exposes /metrics on a private address. It is deliberately not
// on the public listener: the counters say how many games and players exist.
func serveMetrics(ctx context.Context, srv *api.Server) {
	addr, set := os.LookupEnv("METRICS_ADDR")
	if !set {
		addr = "127.0.0.1:9090"
	}
	if addr == "" {
		return
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /metrics", srv.Metrics)
	s := &http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() { <-ctx.Done(); _ = s.Close() }()
	slog.Info("metrics listening", "addr", addr)
	if err := s.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		slog.Error("metrics listen", "err", err)
	}
}

func logLevel() slog.Level {
	var level slog.Level
	if err := level.UnmarshalText([]byte(os.Getenv("LOG_LEVEL"))); err != nil {
		return slog.LevelInfo
	}
	return level
}

// newMux is the routing used by the tests, with a server of its own.
func newMux() *http.ServeMux {
	return newMuxFor(api.NewServer(time.Now, content.Policy(), content.Pick))
}

func newMuxFor(srv *api.Server) *http.ServeMux {
	mux := http.NewServeMux()
	// healthz is liveness: the process is up. readyz is readiness: it is also
	// willing to take new players. They differ only while draining, which is
	// the whole point — a draining instance must stay alive for its games.
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if srv.Draining() {
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"status":"draining","games":` + strconv.Itoa(srv.ActiveGames()) + `}`))
			return
		}
		_, _ = w.Write([]byte(`{"status":"ready"}`))
	})
	srv.Routes(mux)
	return mux
}
