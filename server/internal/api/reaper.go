package api

import (
	"context"
	"log/slog"
	"time"
)

// Nothing in this package used to be deleted: sessions, their reply caches and
// emptied rooms all lived for the life of the process. Organic churn leaked
// slowly and POST /v1/sessions leaked as fast as a stranger could call it.

const (
	// SessionTTL is how long a session with no connection and no room survives.
	// Long enough that a player who closes the app overnight keeps their id.
	SessionTTL = 24 * time.Hour
	// EmptyRoomTTL answers the open decision in docs/open-decisions.md: an
	// empty private room stays joinable by code for this long, so "everyone
	// dropped, we are coming back" works, and is then closed.
	EmptyRoomTTL = 30 * time.Minute
	// BucketIdle is how long a refilled rate-limit bucket is kept.
	BucketIdle = 10 * time.Minute

	reapInterval = time.Minute
)

// Run reaps idle sessions, empty rooms and spent rate-limit buckets until ctx
// is done. Start it once, alongside the HTTP server.
func (s *Server) Run(ctx context.Context) {
	ticker := time.NewTicker(reapInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.reap()
		}
	}
}

func (s *Server) reap() {
	s.mu.Lock()
	defer s.mu.Unlock()
	defer s.recoverRoom(nil, "reaper")
	now := s.now()

	for _, entry := range s.roomsByID {
		switch {
		case !entry.room.Empty():
			entry.emptySince = time.Time{}
		case entry.emptySince.IsZero():
			entry.emptySince = now
		case now.Sub(entry.emptySince) >= EmptyRoomTTL:
			s.dropRoom(entry)
			s.metrics.reapedRooms++
		}
	}

	for token, sess := range s.sessions {
		// Anyone connected, in a room or on a result screen is alive.
		if sess.conn != nil || sess.roomID != "" || sess.gameID != "" {
			sess.lastSeen = now
			continue
		}
		if now.Sub(sess.lastSeen) < SessionTTL {
			continue
		}
		delete(s.sessions, token)
		delete(s.players, sess.playerID)
		s.metrics.reapedSess++
	}

	s.sessionLimit.sweep(now, BucketIdle)
	s.joinLimit.sweep(now, BucketIdle)

	if s.metrics.reapedRooms > 0 || s.metrics.reapedSess > 0 {
		slog.Debug("reaped",
			"rooms", s.metrics.reapedRooms, "sessions", s.metrics.reapedSess,
			"roomsLeft", len(s.roomsByID), "sessionsLeft", len(s.sessions))
	}
}
