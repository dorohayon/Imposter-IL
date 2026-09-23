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
	// UnusedSessionTTL applies to a session that never opened a WebSocket.
	// Creating sessions is unauthenticated, so this — not the per-IP rate
	// limit — is what bounds what an abuser can hold in memory.
	UnusedSessionTTL = 10 * time.Minute
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
	reaper := time.NewTicker(reapInterval)
	bots := time.NewTicker(350 * time.Millisecond)
	defer reaper.Stop()
	defer bots.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-reaper.C:
			s.reap()
		case <-bots.C:
			s.runStagingBots()
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
		// Only a live connection counts as alive. Membership of a room does
		// not: a player who closes the app stays a member so they can come
		// back, and treating that as activity would keep the session — and
		// the room holding it — for the life of the process.
		if sess.conn != nil {
			sess.lastSeen = now
			continue
		}
		ttl := SessionTTL
		if !sess.connected {
			ttl = UnusedSessionTTL // created and never used
		}
		if now.Sub(sess.lastSeen) < ttl {
			continue
		}
		// Take them out of whatever they were in first, so the room can empty
		// and be reaped on a later pass.
		if entry := s.currentRoom(sess); entry != nil {
			s.leave(entry, sess, now)
		}
		sess.leaveGame()
		delete(s.sessions, token)
		delete(s.players, sess.playerID)
		s.metrics.reapedSess++
	}

	s.sessionLimit.sweep(now, BucketIdle)
	s.joinLimit.sweep(now, BucketIdle)
	s.commandLimit.sweep(now, BucketIdle)
	s.entitlementLimit.sweep(now, BucketIdle)
	s.entitlementIPLimit.sweep(now, BucketIdle)

	if s.metrics.reapedRooms > 0 || s.metrics.reapedSess > 0 {
		slog.Debug("reaped",
			"rooms", s.metrics.reapedRooms, "sessions", s.metrics.reapedSess,
			"roomsLeft", len(s.roomsByID), "sessionsLeft", len(s.sessions))
	}
}
