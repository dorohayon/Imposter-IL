package api

// Regressions for defects found in the production-readiness audit
// (September 2026). Each test once reproduced the bug in its name; they now
// pass because the bug is fixed.

import (
	"context"
	"math/rand/v2"
	"net/http/httptest"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
)

// auditLockFree reports whether s.mu can be taken within d.
func auditLockFree(s *Server, d time.Duration) bool {
	got := make(chan struct{})
	go func() { s.mu.Lock(); close(got); s.mu.Unlock() }()
	select {
	case <-got:
		return true
	case <-time.After(d):
		return false
	}
}

// tickSearch walks a snapshot of the members; leaveSearch -> rebalanceStagingBots
// deletes the bots from s.players mid-walk, so the next member is nil.
func TestAuditNoMatchWithStagingBotsDereferencesADeletedBot(t *testing.T) {
	c := newClient(t)
	c.srv.EnableStagingBots(5)
	h1 := c.searcher("אחד", "film_tv")
	h2 := c.searcher("שתיים", "film_tv")
	h3 := c.searcher("שלוש", "film_tv")
	c.waitStagingSearchPlayers(4) // three humans, one bot
	c.advance(5 * time.Second)
	// Two humans cancel; the room is back to one human and one bot, and the
	// replacement bots are still pending when H1's two minutes run out.
	wantOK(t, h2.w.command("c2", "matchmaking.cancel", nil))
	wantOK(t, h3.w.command("c3", "matchmaking.cancel", nil))
	c.srv.mu.Lock()
	entry := c.srv.roomsByID[c.srv.players[h1.id].roomID]
	members := entry.room.View().Members
	started := c.srv.players[h1.id].searchStarted
	c.srv.mu.Unlock()
	t.Logf("members before the no-match deadline: %d", len(members))
	c.clock.Store(started.Add(2 * time.Minute).UnixNano())

	// Exactly what the room timer runs (ws.go schedule).
	func() {
		c.srv.mu.Lock()
		defer c.srv.mu.Unlock()
		defer c.srv.recoverRoom(entry, "timer")
		c.srv.tickRoom(entry)
	}()
	c.srv.mu.Lock()
	panics, aborted := c.srv.metrics.panics, c.srv.metrics.aborted
	c.srv.mu.Unlock()
	if panics != 0 {
		t.Errorf("timer path panicked %d time(s), room aborted %d", panics, aborted)
	}
}

// The same stale-snapshot walk reached from runStagingBots, which has no
// recover: in production (Server.Run goroutine) this panic ends the process.
func TestAuditNoMatchInPlayAgainRoomPanicsTheBotLoop(t *testing.T) {
	c := newClient(t)
	hs := c.searchers(4, "film_tv")
	c.advance(30 * time.Second)
	c.tickAll()
	var gameIDs []string
	for _, h := range hs {
		gameIDs = append(gameIDs, h.w.sessionState(func(s map[string]any) bool { return s["activity"] == "game" })["gameId"].(string))
	}
	// Two walk out: the match ends for lack of players (or on the impostor leaving).
	wantOK(t, hs[2].w.command("l2", "game.leave", map[string]any{"gameId": gameIDs[2]}))
	wantOK(t, hs[3].w.command("l3", "game.leave", map[string]any{"gameId": gameIDs[3]}))
	c.srv.EnableStagingBots(5)
	wantOK(t, hs[0].w.command("p0", "game.playAgain", map[string]any{"gameId": gameIDs[0]}))
	wantOK(t, hs[1].w.command("p1", "game.playAgain", map[string]any{"gameId": gameIDs[1]}))
	c.srv.mu.Lock()
	sess := c.srv.players[hs[0].id]
	entry := c.srv.roomsByID[sess.roomID]
	deadline := sess.searchStarted.Add(2 * time.Minute)
	ended := entry.room.Game() != nil && entry.room.Game().Phase() == "ended"
	c.srv.mu.Unlock()
	if !ended {
		t.Fatal("setup: play-again room should still hold the ended game")
	}
	// hs[1] gives up a moment before hs[0]'s two minutes are up.
	c.clock.Store(deadline.Add(-time.Millisecond).UnixNano())
	wantOK(t, hs[1].w.command("c1", "matchmaking.cancel", nil))
	c.clock.Store(deadline.UnixNano())
	c.srv.mu.Lock()
	t.Logf("members at the deadline: %d", len(entry.room.View().Members))
	c.srv.mu.Unlock()

	var recovered any
	func() {
		defer func() { recovered = recover() }()
		c.srv.runStagingBots() // Server.Run calls this every 350ms with no recover
	}()
	if recovered != nil {
		t.Errorf("runStagingBots panicked (process crash in production): %v", recovered)
	}
}

// PATCH /v1/sessions/me has no rate limit and publishes the whole room
// (room.state + game.state to every member) even when nothing changed. queue()
// disconnects any member whose 64-message buffer is full. A member reading at
// 500 messages/s (a phone on a modest link) is knocked offline, and in a game
// every such disconnect is counted.
func TestAuditProfileFloodDisconnectsTheTable(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(6)
	gameID, _ := c.startGame(roomID, players)
	attacker, victims := players[0], players[1:]
	for _, v := range victims {
		go func(ws *websocket.Conn) {
			for {
				if _, _, err := ws.Read(context.Background()); err != nil {
					return
				}
				time.Sleep(2 * time.Millisecond)
			}
		}(v.w.ws)
	}
	go func(ws *websocket.Conn) { // the attacker reads everything, fast
		for {
			if _, _, err := ws.Read(context.Background()); err != nil {
				return
			}
		}
	}(attacker.w.ws)

	var sent atomic.Int64
	stop := time.Now().Add(2 * time.Second)
	var wg sync.WaitGroup
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for time.Now().Before(stop) {
				req := httptest.NewRequest("PATCH", "/v1/sessions/me", strings.NewReader("{}"))
				req.Header.Set("Authorization", "Bearer "+attacker.token)
				c.mux.ServeHTTP(httptest.NewRecorder(), req)
				sent.Add(1)
			}
		}()
	}
	wg.Wait()
	time.Sleep(200 * time.Millisecond)

	c.srv.mu.Lock()
	g := c.srv.roomsByID[roomID].room.Game()
	v, _ := g.View(attacker.id)
	offline := 0
	for _, p := range v.Players {
		if p.ID != attacker.id && (!p.Connected || p.Disconnects > 0) {
			offline++
		}
	}
	rl := c.srv.metrics.rateLimited
	c.srv.mu.Unlock()
	t.Logf("game %s: %d empty PATCH requests in 2s (rate limited: %d); victims disconnected: %d of %d", gameID, sent.Load(), rl, offline, len(victims))
	if offline > 0 {
		t.Errorf("one player's unlimited PATCH flood disconnected %d of %d other players mid-game", offline, len(victims))
	}
}

// A WebSocket that attaches to a session the reaper deleted between serveWS's
// lookup and attach becomes a session that is in no map. Deterministic
// version: the state the reaper leaves, then one command.
func TestAuditGhostSessionDeadlocksTheServer(t *testing.T) {
	c := newClient(t)
	token, id := c.session("רפאים")
	w := c.dial(token)
	w.sessionState(func(map[string]any) bool { return true })
	c.srv.mu.Lock()
	delete(c.srv.sessions, token) // what reap() does if it runs in the window
	delete(c.srv.players, id)
	c.srv.mu.Unlock()

	w.send(map[string]any{"v": 1, "id": "j", "type": "matchmaking.join", "payload": map[string]any{"categoryIds": []string{"film_tv"}}})
	time.Sleep(300 * time.Millisecond)
	if !auditLockFree(c.srv, 3*time.Second) {
		buf := make([]byte, 1<<16)
		n := runtime.Stack(buf, true)
		stack := string(buf[:n])
		t.Errorf("server lock is held forever after one command from a reaped session (global deadlock); readLoop in stacks: %v", strings.Contains(stack, "readLoop"))
		t.Logf("%s", stack)
		t.SkipNow() // leaves the server deadlocked; cleanup that needs the lock would hang
	}
}

// How often does the natural race produce that state? reap() and a WebSocket
// handshake for a session whose TTL has passed, started together.
func TestAuditReaperRacesTheHandshake(t *testing.T) {
	c := newClient(t)
	ghosts := 0
	const tries = 300
	for range tries {
		token, _ := c.session("מרוץ")
		c.srv.mu.Lock()
		sess := c.srv.sessions[token]
		c.srv.mu.Unlock()
		c.advance(UnusedSessionTTL + time.Minute)
		done := make(chan *websocket.Conn)
		go func() {
			ws, _, err := c.dialRaw(token)
			if err != nil {
				done <- nil
				return
			}
			done <- ws
		}()
		time.Sleep(time.Duration(rand.IntN(3000)) * time.Microsecond)
		c.srv.reap()
		ws := <-done
		time.Sleep(20 * time.Millisecond)
		c.srv.mu.Lock()
		if c.srv.sessions[token] == nil && sess.conn != nil {
			ghosts++
		}
		c.srv.mu.Unlock()
		if ws != nil {
			_ = ws.CloseNow()
		}
	}
	t.Logf("ghost sessions (socket attached to a reaped session): %d of %d", ghosts, tries)
}
