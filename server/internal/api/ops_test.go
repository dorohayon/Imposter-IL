package api

import (
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
		"maxPlayers": 4, "hintSeconds": 15, "categoryIds": []string{"animals"},
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

	// A session in a room is never reaped, however long it idles.
	c.advance(SessionTTL + time.Hour)
	c.srv.reap()
	if len(c.srv.sessions) != 1 {
		t.Fatalf("sessions = %d, want the one still in a room", len(c.srv.sessions))
	}

	// Once it is out of the room and idle, it goes.
	c.srv.mu.Lock()
	sess := c.srv.sessions[token]
	sess.roomID, sess.lastSeen = "", c.srv.now().Add(-SessionTTL-time.Minute)
	c.srv.mu.Unlock()
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
		"maxPlayers": 4, "hintSeconds": 15, "categoryIds": []string{"animals"},
	})
	c.wantError(http.StatusServiceUnavailable, "server_draining", status, got)

	other, _ := c.session("נועה")
	status, got = c.join(other, room["code"].(string))
	c.wantError(http.StatusServiceUnavailable, "server_draining", status, got)

	w := c.dial(other)
	wantReplyError(t, w.command("m", "matchmaking.join", map[string]any{"categoryIds": []string{"animals"}}), "server_draining")
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
	r.RemoteAddr = "203.0.113.9:4444"
	r.Header.Set("X-Forwarded-For", "198.51.100.1, 203.0.113.9")

	if got := c.srv.clientIP(r); got != "203.0.113.9" {
		t.Fatalf("untrusted proxy: got %q, want the peer address", got)
	}
	c.srv.TrustProxy(true)
	if got := c.srv.clientIP(r); got != "198.51.100.1" {
		t.Fatalf("trusted proxy: got %q, want the forwarded client", got)
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
