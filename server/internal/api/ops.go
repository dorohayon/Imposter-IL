package api

import (
	"fmt"
	"log/slog"
	"maps"
	"net/http"
	"runtime"
	"runtime/debug"
	"slices"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/room"
)

// Operational surface: counters and /metrics, draining for a deploy that does
// not kill live games, and panic recovery that costs one room instead of the
// whole process.
//
// Everything here runs under s.mu, like the rest of the package.

// metrics are plain counters read by the /metrics handler under s.mu.
type metrics struct {
	commands     map[string]int64 // error code, "" for success
	panics       int64
	aborted      int64
	rateLimited  int64
	reports      int64
	reapedRooms  int64
	reapedSess   int64
	wsConns      int64
	publishNanos int64
	publishCount int64
}

// ---------------------------------------------------------------- draining

// Drain stops the server taking on new activity: no new rooms, no new online
// searches and no new games. Games already in progress finish normally. Call
// it on SIGTERM, wait for ActiveGames to reach zero, then shut the server
// down. Without this a deploy ends every game in flight (there is no
// persistence), which in practice means never deploying during the day.
func (s *Server) Drain() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.draining = true
	slog.Info("draining", "activeGames", s.activeGames())
}

// Draining reports whether the server is shutting down. /readyz uses it so
// the load balancer stops sending new players here.
func (s *Server) Draining() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.draining
}

// ActiveGames counts rooms with a game in progress.
func (s *Server) ActiveGames() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.activeGames()
}

func (s *Server) activeGames() int {
	n := 0
	for _, entry := range s.roomsByID {
		if g := entry.room.Game(); g != nil && entry.room.View().Status == room.StatusInGame {
			n++
		}
	}
	return n
}

// ---------------------------------------------------------------- recovery

// abortRoom drops a room and tells everyone in it that the server failed.
// No loss is recorded: docs/protocol.md game.aborted, screen 29.
//
// It walks sessions instead of the room's member list on purpose — the room's
// own state is what just panicked, so it is not to be trusted here.
func (s *Server) abortRoom(entry *roomEntry) {
	now := s.now()
	msg := message("game.aborted", now, map[string]any{
		"gameId": entry.gameID, "reason": "server_error", "lossRecorded": false,
	})
	for _, sess := range s.players {
		if sess.gameRoom != entry && sess.roomID != entry.id {
			continue
		}
		if sess.gameRoom == entry {
			s.queue(sess.conn, msg)
		}
		sess.roomID = ""
		sess.leaveGame()
		s.sendSessionState(sess)
	}
	s.dropRoom(entry)
	s.metrics.aborted++
}

// dropRoom forgets a room and stops its timer.
func (s *Server) dropRoom(entry *roomEntry) {
	if entry.timer != nil {
		entry.timer.Stop()
		entry.timer = nil
	}
	delete(s.roomsByID, entry.id)
	if !entry.public && entry.code != "" {
		delete(s.roomsCode, entry.code)
	}
	s.publicRooms = slices.DeleteFunc(s.publicRooms, func(e *roomEntry) bool { return e == entry })
}

// recoverRoom turns a panic into an aborted room. Deferred *after* the lock is
// taken and before it is released, so it still holds s.mu when it runs.
func (s *Server) recoverRoom(entry *roomEntry, where string) {
	r := recover()
	if r == nil {
		return
	}
	s.panicked(where, r)
	if entry != nil {
		s.abortRoom(entry)
	}
}

func (s *Server) panicked(where string, r any) {
	s.metrics.panics++
	slog.Error("panic recovered",
		"where", where, "panic", fmt.Sprint(r), "stack", string(debug.Stack()))
}

// safely runs fn in a goroutine that logs a panic instead of ending the
// process. For goroutines that touch no shared state (socket readers and
// writers), so there is no room to abort.
func (s *Server) safely(where string, fn func()) {
	go func() {
		defer func() {
			if r := recover(); r != nil {
				s.mu.Lock()
				s.panicked(where, r)
				s.mu.Unlock()
			}
		}()
		fn()
	}()
}

// ----------------------------------------------------------------- metrics

// Metrics writes the counters in Prometheus text format. Wire it on an
// address that is not public, or behind the reverse proxy.
func (s *Server) Metrics(w http.ResponseWriter, _ *http.Request) {
	s.mu.Lock()
	games, rooms, sessions, conns := s.activeGames(), len(s.roomsByID), len(s.sessions), s.metrics.wsConns
	searching := len(s.publicRooms)
	m := s.metrics
	commands := maps.Clone(m.commands)
	draining := s.draining
	s.mu.Unlock()

	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	p := func(name, typ, help string, value any) {
		_, _ = fmt.Fprintf(w, "# HELP %s %s\n# TYPE %s %s\n%s %v\n", name, help, name, typ, name, value)
	}
	p("imposter_games_active", "gauge", "Games in progress.", games)
	p("imposter_rooms", "gauge", "Rooms held in memory, private and online.", rooms)
	p("imposter_searches_active", "gauge", "Online matches still forming.", searching)
	p("imposter_sessions", "gauge", "Guest sessions held in memory.", sessions)
	p("imposter_ws_connections", "gauge", "Open WebSocket connections.", conns)
	p("imposter_goroutines", "gauge", "Runtime goroutines.", runtime.NumGoroutine())
	p("imposter_draining", "gauge", "1 while the server is draining for shutdown.", boolValue(draining))
	p("imposter_panics_total", "counter", "Panics recovered.", m.panics)
	p("imposter_games_aborted_total", "counter", "Games ended by server error.", m.aborted)
	p("imposter_rate_limited_total", "counter", "Requests and commands refused by a rate limit.", m.rateLimited)
	p("imposter_reports_total", "counter", "Players reported for their hints or nickname.", m.reports)
	p("imposter_reaped_rooms_total", "counter", "Empty rooms closed by the reaper.", m.reapedRooms)
	p("imposter_reaped_sessions_total", "counter", "Idle sessions dropped by the reaper.", m.reapedSess)
	p("imposter_publish_seconds_sum", "counter", "Time spent building and queueing snapshots.", float64(m.publishNanos)/1e9)
	p("imposter_publish_total", "counter", "Snapshot publishes.", m.publishCount)

	// One series per error code, so a spike in any one is visible.
	_, _ = fmt.Fprintf(w, "# HELP imposter_commands_total Client commands by result.\n# TYPE imposter_commands_total counter\n")
	for _, code := range slices.Sorted(maps.Keys(commands)) {
		result := code
		if result == "" {
			result = "ok"
		}
		_, _ = fmt.Fprintf(w, "imposter_commands_total{result=%q} %d\n", result, commands[code])
	}

	var mem runtime.MemStats
	runtime.ReadMemStats(&mem)
	p("imposter_heap_bytes", "gauge", "Heap in use.", mem.HeapAlloc)
}

func boolValue(b bool) int {
	if b {
		return 1
	}
	return 0
}

func (s *Server) countCommand(code string) {
	if s.metrics.commands == nil {
		s.metrics.commands = map[string]int64{}
	}
	s.metrics.commands[code]++
}

// timePublish records how long a publish held the lock, so the ceiling of the
// single-lock design is a measurement rather than a guess.
func (s *Server) timePublish(start time.Time) {
	s.metrics.publishNanos += int64(time.Since(start))
	s.metrics.publishCount++
}
