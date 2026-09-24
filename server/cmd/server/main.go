// Command server runs the מי המתחזה? backend.
package main

import (
	"cmp"
	"context"
	"crypto/subtle"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/api"
	"github.com/dorohayon/Imposter-IL/server/internal/content"
	"github.com/dorohayon/Imposter-IL/server/internal/invite"
	"github.com/dorohayon/Imposter-IL/server/internal/legal"
	"github.com/dorohayon/Imposter-IL/server/internal/monetization"
)

// Environment:
//
//	PORT           listen port (default 8080)
//	METRICS_ADDR   private /metrics listener (default 127.0.0.1:9090, "" to disable)
//	METRICS_TOKEN  also serve /metrics on the public port behind this bearer
//	               token, for hosts with no way to reach loopback (Cloud Run)
//	TRUST_PROXY    "1" to read the client address from X-Forwarded-For
//	RATE_LIMITS    "off" for load tests only; never in production
//	DRAIN_TIMEOUT  how long to let games finish on SIGTERM (default 10m)
//	MIN_CLIENT_BUILD  oldest app build served (default 0: every client)
//	STAGING_BOTS   server-side online bots (0-5; default 0, never enable in prod)
//	LOG_LEVEL      debug | info | warn | error (default info)
//	MONETIZATION_CONFIG  JSON over monetization.Default() (docs/monetization.md)
//	APPLE_BUNDLE_ID      verify StoreKit 2 purchases for this bundle id
//	GOOGLE_PLAY_PACKAGE  verify Play purchases for this package name, with
//	GOOGLE_PLAY_SERVICE_ACCOUNT  the service account key file's JSON (a secret)
func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: logLevel()})))

	srv := api.NewServer(time.Now, content.Policy(), content.Pick)
	if bots, err := strconv.Atoi(os.Getenv("STAGING_BOTS")); err == nil && bots > 0 {
		srv.EnableStagingBots(bots)
		slog.Warn("staging bots enabled", "count", min(bots, 5))
	}
	cfg, verifiers, err := monetizationFromEnv()
	if err != nil {
		slog.Error("monetization", "err", err)
		os.Exit(1)
	}
	srv.SetMonetization(cfg, verifiers)
	if cfg.ServerEnforcement && len(verifiers) < 2 {
		slog.Warn("serverEnforcement is on without both store verifiers: purchases on the unverified platform are refused online",
			"verifiers", len(verifiers))
	}
	srv.TrustProxy(os.Getenv("TRUST_PROXY") == "1")
	if os.Getenv("RATE_LIMITS") == "off" {
		// For cmd/loadbot, whose simulated players all dial from one address.
		srv.DisableRateLimits()
		slog.Warn("rate limits disabled: load testing only, never in production")
	}
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

// monetizationFromEnv reads the pricing model and the store credentials. A
// config that does not parse stops the server: running on defaults would
// quietly change what players are charged for.
func monetizationFromEnv() (monetization.Config, map[string]monetization.Verifier, error) {
	cfg := monetization.Default()
	if raw := os.Getenv("MONETIZATION_CONFIG"); raw != "" {
		var err error
		if cfg, err = monetization.Parse([]byte(raw)); err != nil {
			return cfg, nil, err
		}
	}
	verifiers := map[string]monetization.Verifier{}
	if bundle := os.Getenv("APPLE_BUNDLE_ID"); bundle != "" {
		verifiers["ios"] = monetization.NewAppleVerifier(bundle)
	}
	if pkg := os.Getenv("GOOGLE_PLAY_PACKAGE"); pkg != "" {
		google, err := monetization.NewGoogleVerifier(pkg, []byte(os.Getenv("GOOGLE_PLAY_SERVICE_ACCOUNT")))
		if err != nil {
			return cfg, nil, err
		}
		verifiers["android"] = google
	}
	return cfg, verifiers, nil
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
	// On a host with no shell (Cloud Run), loopback is unreachable, so the
	// only way to read the counters is over the public port. Behind a bearer
	// token, because they say how many games and players exist.
	if token := os.Getenv("METRICS_TOKEN"); token != "" {
		mux.HandleFunc("GET /metrics", func(w http.ResponseWriter, r *http.Request) {
			got, _ := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
			if subtle.ConstantTimeCompare([]byte(got), []byte(token)) != 1 {
				w.WriteHeader(http.StatusNotFound)
				return
			}
			srv.Metrics(w, r)
		})
	}
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if srv.Draining() {
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"status":"draining","games":` + strconv.Itoa(srv.ActiveGames()) + `}`))
			return
		}
		_, _ = w.Write([]byte(`{"status":"ready"}`))
	})
	legal.Routes(mux)
	invite.Routes(mux)
	srv.Routes(mux)
	return mux
}
