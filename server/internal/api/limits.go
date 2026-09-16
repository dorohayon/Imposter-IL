package api

import (
	"net"
	"net/http"
	"strings"
	"time"
)

// Token-bucket rate limits for the codes docs/protocol.md already defines.
//
// These are the only abuse control the product has: there are no accounts, so
// there is no identity to ban. Without them POST /v1/sessions is unauthenticated
// unbounded allocation, and the six-digit room code space can be enumerated in
// minutes to walk into strangers' private rooms.
//
// Every limiter is called under s.mu, so it needs no lock of its own.

// Defaults. Generous enough that no human playing the game meets them.
const (
	sessionsPerMinute = 5  // guest sessions per IP
	sessionsBurst     = 5  // a reinstall loop is a handful, not hundreds
	joinsPerMinute    = 10 // room-code attempts per IP: 10^6 codes takes centuries
	joinsBurst        = 10
	commandsPerMinute = 600 // 10/s per session; reactions are unlimited by product rule
	commandsBurst     = 60
)

type bucket struct {
	tokens float64
	last   time.Time
}

type limiter struct {
	rate    float64 // tokens per second
	burst   float64
	buckets map[string]*bucket
}

func newLimiter(perMinute, burst float64) *limiter {
	return &limiter{rate: perMinute / 60, burst: burst, buckets: map[string]*bucket{}}
}

// allow takes one token for key, refilling first. A zero rate disables the
// limiter, which is what tests and local runs want.
func (l *limiter) allow(key string, now time.Time) bool {
	if l == nil || l.rate <= 0 {
		return true
	}
	b := l.buckets[key]
	if b == nil {
		b = &bucket{tokens: l.burst, last: now}
		l.buckets[key] = b
	}
	if elapsed := now.Sub(b.last); elapsed > 0 {
		b.tokens = min(l.burst, b.tokens+elapsed.Seconds()*l.rate)
		b.last = now
	}
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

// sweep forgets buckets that have refilled and gone quiet, so the limiter is
// not itself a memory leak. Called by the reaper.
func (l *limiter) sweep(now time.Time, idle time.Duration) {
	if l == nil {
		return
	}
	for key, b := range l.buckets {
		if b.tokens >= l.burst && now.Sub(b.last) > idle {
			delete(l.buckets, key)
		}
	}
}

// clientIP identifies the caller for per-IP limits.
//
// X-Forwarded-For is honoured only when the server is explicitly told it sits
// behind a proxy (TRUST_PROXY=1). A directly exposed server that trusted the
// header would let any client forge it and walk straight past every limit.
func (s *Server) clientIP(r *http.Request) string {
	if s.trustProxy {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			return strings.TrimSpace(strings.Split(xff, ",")[0])
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// TrustProxy makes the server read the client address from X-Forwarded-For.
// Set it only when a reverse proxy you control is the sole way in.
func (s *Server) TrustProxy(trust bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.trustProxy = trust
}

var errRateLimited = apiError{http.StatusTooManyRequests, "rate_limited", "too many requests"}
