package api

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestRateLimits(t *testing.T) {
	c := newClient(t)
	c.srv.sessionLimit = newLimiter(sessionsPerMinute, sessionsBurst)
	c.srv.joinLimit = newLimiter(joinsPerMinute, joinsBurst)

	body := map[string]string{"nickname": "דור", "avatarId": "avatar-m04-detective-hat"}
	for i := range sessionsBurst {
		if status, got := c.do("POST", "/v1/sessions", "", body); status != http.StatusCreated {
			t.Fatalf("session %d: %d %v", i, status, got)
		}
	}
	status, got := c.do("POST", "/v1/sessions", "", body)
	c.wantError(http.StatusTooManyRequests, "rate_limited", status, got)

	// The bucket refills, so a real player who waits gets in.
	c.advance(time.Minute)
	if status, got := c.do("POST", "/v1/sessions", "", body); status != http.StatusCreated {
		t.Fatalf("after refill: %d %v", status, got)
	}

	// Room-code enumeration is limited before the code is even looked up.
	token, _ := c.session("נועה")
	for range joinsBurst {
		c.join(token, "000001")
	}
	status, got = c.join(token, "000001")
	c.wantError(http.StatusTooManyRequests, "rate_limited", status, got)
}

func TestCommandRateLimitRepliesAndRecovers(t *testing.T) {
	c := newClient(t)
	c.srv.commandLimit = newLimiter(60, 2) // 1/s, burst 2
	token, _ := c.session("דור")
	w := c.dial(token)

	wantOK(t, w.command("a", "matchmaking.cancel", map[string]any{}))
	wantOK(t, w.command("b", "matchmaking.cancel", map[string]any{}))
	wantReplyError(t, w.command("c", "matchmaking.cancel", map[string]any{}), "rate_limited")

	c.advance(2 * time.Second)
	wantOK(t, w.command("d", "matchmaking.cancel", map[string]any{}))
}

func TestReaperDropsEmptyRoomsAndIdleSessions(t *testing.T) {
	c := newClient(t)
	token, _ := c.session("דור")
	room := c.createRoom(token, 4)
	code := room["code"].(string)

	if status, got := c.do("POST", "/v1/rooms", token, map[string]any{
		"maxPlayers": 4, "hintSeconds": 60, "categoryIds": []string{"film_tv"},
	}); status != http.StatusCreated {
		t.Fatalf("second room: %d %v", status, got) // leaves the first one empty
	}

	c.srv.reap() // not yet: the room is only now marked empty
	if _, joinable := c.srv.roomsCode[code]; !joinable {
		t.Fatal("room dropped before its TTL")
	}
	c.advance(EmptyRoomTTL + time.Minute)
	c.srv.reap()
	if _, joinable := c.srv.roomsCode[code]; joinable {
		t.Fatal("empty room outlived its TTL")
	}

	// Room membership is not activity: with no connection the session ages
	// out like any other, and is taken out of the room on the way.
	// TestReaperDropsAbandonedRoomMembers covers that from the socket side.
	c.advance(SessionTTL + time.Hour)
	c.srv.reap()
	if len(c.srv.sessions) != 0 || len(c.srv.players) != 0 {
		t.Fatalf("sessions %d players %d, want none", len(c.srv.sessions), len(c.srv.players))
	}
}

func TestDrainRefusesNewActivityButNotLiveGames(t *testing.T) {
	c := newClient(t)
	token, _ := c.session("דור")
	room := c.createRoom(token, 4)

	c.srv.Drain()
	if !c.srv.Draining() {
		t.Fatal("not draining")
	}

	status, got := c.do("POST", "/v1/rooms", token, map[string]any{
		"maxPlayers": 4, "hintSeconds": 60, "categoryIds": []string{"film_tv"},
	})
	c.wantError(http.StatusServiceUnavailable, "server_draining", status, got)

	other, _ := c.session("נועה")
	status, got = c.join(other, room["code"].(string))
	c.wantError(http.StatusServiceUnavailable, "server_draining", status, got)

	w := c.dial(other)
	wantReplyError(t, w.command("m", "matchmaking.join", map[string]any{"categoryIds": []string{"film_tv"}}), "server_draining")
}

// A panic inside a room must cost that room, not the process: its players are
// told the server failed, no loss is recorded, and everyone else plays on.
func TestPanicAbortsOnlyItsOwnRoom(t *testing.T) {
	c := newClient(t)
	token, _ := c.session("דור")
	room := c.createRoom(token, 4)
	w := c.dial(token)
	w.roomState(func(map[string]any) bool { return true })

	c.srv.mu.Lock()
	entry := c.srv.roomsByID[room["roomId"].(string)]
	sess := c.srv.sessions[token]
	sess.gameRoom, sess.gameID = entry, "g_test"
	c.srv.mu.Unlock()

	c.srv.mu.Lock()
	func() {
		defer c.srv.recoverRoom(entry, "test")
		panic("boom")
	}()
	c.srv.mu.Unlock()

	payload := w.next("game.aborted")["payload"].(map[string]any)
	if payload["reason"] != "server_error" || payload["lossRecorded"] != false {
		t.Fatalf("game.aborted = %v", payload)
	}
	if _, alive := c.srv.roomsByID[room["roomId"].(string)]; alive {
		t.Fatal("aborted room still registered")
	}
	if c.srv.metrics.panics != 1 || c.srv.metrics.aborted != 1 {
		t.Fatalf("panics %d aborted %d, want 1 and 1", c.srv.metrics.panics, c.srv.metrics.aborted)
	}

	// The server is still usable afterwards.
	if _, _ = c.session("יעל"); len(c.srv.sessions) != 2 {
		t.Fatalf("sessions = %d, want 2", len(c.srv.sessions))
	}
}

func TestMetricsRender(t *testing.T) {
	c := newClient(t)
	token, _ := c.session("דור")
	c.createRoom(token, 4)

	rec := httptest.NewRecorder()
	c.srv.Metrics(rec, httptest.NewRequest("GET", "/metrics", nil))
	out := rec.Body.String()
	for _, want := range []string{
		"imposter_games_active 0",
		"imposter_rooms 1",
		"imposter_sessions 1",
		"imposter_panics_total 0",
		"imposter_goroutines",
		"imposter_heap_bytes",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("metrics missing %q in:\n%s", want, out)
		}
	}
}

func TestClientIPTrustsForwardedHeaderOnlyWhenTold(t *testing.T) {
	c := newClient(t)
	r := httptest.NewRequest("POST", "/v1/sessions", nil)
	r.RemoteAddr = "10.1.2.3:4444"
	// The client forged the first hop; the proxy appended what it really saw.
	r.Header.Set("X-Forwarded-For", "198.51.100.1, 203.0.113.9")

	if got := c.srv.clientIP(r); got != "10.1.2.3" {
		t.Fatalf("untrusted proxy: got %q, want the peer address", got)
	}
	c.srv.TrustProxy(true)
	if got := c.srv.clientIP(r); got != "203.0.113.9" {
		t.Fatalf("trusted proxy: got %q, want the address the proxy appended", got)
	}
}

// A forged X-Forwarded-For must not buy a fresh rate-limit bucket per request.
func TestForgedForwardedHeaderDoesNotBypassSessionLimit(t *testing.T) {
	c := newClient(t)
	c.srv.TrustProxy(true)
	c.srv.sessionLimit = newLimiter(sessionsPerMinute, sessionsBurst)
	limited := 0
	for i := range sessionsBurst + 5 {
		r := httptest.NewRequest("POST", "/v1/sessions", strings.NewReader(`{"nickname":"שחקן","avatarId":"avatar-m04-detective-hat"}`))
		r.Header.Set("X-Forwarded-For", fmt.Sprintf("10.0.0.%d, 203.0.113.9", i))
		w := httptest.NewRecorder()
		c.srv.createSession(w, r)
		if w.Code == http.StatusTooManyRequests {
			limited++
		}
	}
	if limited == 0 {
		t.Fatal("rotating the forged first hop bypassed the per-IP session limit")
	}
}

func TestClientBuildGate(t *testing.T) {
	c := newClient(t)
	body := map[string]string{"nickname": "דור", "avatarId": "avatar-m04-detective-hat"}

	// No minimum: a client that sends no header at all is served.
	if status, got := c.do("POST", "/v1/sessions", "", body); status != http.StatusCreated {
		t.Fatalf("ungated: %d %v", status, got)
	}

	c.srv.RequireClientBuild(7)
	status, got := c.do("POST", "/v1/sessions", "", body)
	c.wantError(http.StatusUpgradeRequired, "client_too_old", status, got)

	for _, build := range []string{"6", "nonsense", ""} {
		req := httptest.NewRequest("POST", "/v1/sessions", strings.NewReader(`{"nickname":"דור","avatarId":"avatar-m04-detective-hat"}`))
		req.Header.Set("X-Client-Build", build)
		rec := httptest.NewRecorder()
		c.mux.ServeHTTP(rec, req)
		if rec.Code != http.StatusUpgradeRequired {
			t.Fatalf("build %q: got %d, want 426", build, rec.Code)
		}
	}

	req := httptest.NewRequest("POST", "/v1/sessions", strings.NewReader(`{"nickname":"דור","avatarId":"avatar-m04-detective-hat"}`))
	req.Header.Set("X-Client-Build", "7")
	rec := httptest.NewRecorder()
	c.mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("build at the minimum: got %d %q", rec.Code, rec.Body.String())
	}
}

// Creating sessions is unauthenticated, so memory is bounded by reaping the
// ones that never connect — not by a per-IP rate low enough to lock out a
// mobile carrier's NAT.
func TestUnusedSessionsAreReapedQuickly(t *testing.T) {
	c := newClient(t)
	c.session("דור") // created, never connects a WebSocket

	c.advance(UnusedSessionTTL - time.Minute)
	c.srv.reap()
	if len(c.srv.sessions) != 1 {
		t.Fatal("reaped before its TTL")
	}

	c.advance(2 * time.Minute)
	c.srv.reap()
	if len(c.srv.sessions) != 0 {
		t.Fatal("an unused session outlived UnusedSessionTTL")
	}

	// One that has actually connected keeps the long TTL.
	connected, _ := c.session("נועה")
	c.dial(connected)
	c.advance(UnusedSessionTTL + time.Minute)
	c.srv.reap()
	if len(c.srv.sessions) != 1 {
		t.Fatal("a session that connected was reaped as unused")
	}
}

// A used bucket never climbs back to burst on its own, so sweeping on the
// stored token count would have kept every bucket forever.
func TestLimiterSweepDropsIdleBuckets(t *testing.T) {
	l := newLimiter(60, 5)
	now := t0
	l.allow("a", now)
	l.allow("b", now)
	if len(l.buckets) != 2 {
		t.Fatalf("buckets = %d, want 2", len(l.buckets))
	}

	l.sweep(now.Add(time.Minute), BucketIdle)
	if len(l.buckets) != 2 {
		t.Fatal("swept a bucket that was still recent")
	}
	l.sweep(now.Add(BucketIdle+time.Minute), BucketIdle)
	if len(l.buckets) != 0 {
		t.Fatalf("buckets = %d after going idle, want 0", len(l.buckets))
	}
}

// A player who closes the app stays a room member so they can return. That
// must not keep the session, or the room, alive for the life of the process.
func TestReaperDropsAbandonedRoomMembers(t *testing.T) {
	c := newClient(t)
	token, id := c.session("דור")
	room := c.createRoom(token, 4)
	code := room["code"].(string)

	// Connect and drop, the way closing the app does.
	w := c.dial(token)
	w.roomState(func(map[string]any) bool { return true })
	_ = w.ws.CloseNow()
	waitFor(t, func() bool {
		c.srv.mu.Lock()
		defer c.srv.mu.Unlock()
		return c.srv.sessions[token].conn == nil
	})

	c.advance(SessionTTL + time.Hour)
	c.srv.reap()
	if _, alive := c.srv.sessions[token]; alive {
		t.Fatal("an abandoned session survived its TTL because it held a roomId")
	}
	if _, alive := c.srv.players[id]; alive {
		t.Fatal("player entry left behind")
	}

	// With its last member gone the room is empty, so the next passes drop it.
	c.srv.reap()
	c.advance(EmptyRoomTTL + time.Minute)
	c.srv.reap()
	if _, alive := c.srv.roomsCode[code]; alive {
		t.Fatal("the room outlived every member")
	}
}

func waitFor(t *testing.T, ok func() bool) {
	t.Helper()
	for range 100 {
		if ok() {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("condition not reached")
}

// When draining runs out, players get game.aborted with no loss rather than a
// socket that simply dies.
func TestAbortGamesTellsPlayersNoLossWasRecorded(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(4)
	gameID, _ := c.startGame(roomID, players)

	c.srv.AbortGames()
	for _, p := range players {
		msg := p.w.next("game.aborted")["payload"].(map[string]any)
		if msg["gameId"] != gameID || msg["lossRecorded"] != false {
			t.Fatalf("game.aborted = %v", msg)
		}
	}
	if n := c.srv.ActiveGames(); n != 0 {
		t.Fatalf("%d games still active after AbortGames", n)
	}
}
