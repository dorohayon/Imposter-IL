package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

var t0 = time.Date(2026, 9, 15, 12, 0, 0, 0, time.UTC)

type client struct {
	t     *testing.T
	mux   *http.ServeMux
	srv   *Server
	ts    *httptest.Server
	clock atomic.Int64 // server time in unix nanoseconds
}

func newClient(t *testing.T) *client {
	policy := game.Policy{
		HintInappropriate: func(string) bool { return false },
		ValidReaction:     func(string) bool { return true },
	}
	c := &client{t: t, mux: http.NewServeMux()}
	c.clock.Store(t0.UnixNano())
	c.srv = NewServer(func() time.Time { return time.Unix(0, c.clock.Load()).UTC() }, policy)
	c.srv.Routes(c.mux)
	c.ts = httptest.NewServer(c.mux)
	t.Cleanup(c.ts.Close)
	return c
}

func (c *client) advance(d time.Duration) { c.clock.Add(int64(d)) }

// do sends body as JSON (raw when it is a string) and decodes the response.
func (c *client) do(method, path, token string, body any) (int, map[string]any) {
	c.t.Helper()
	raw, ok := body.(string)
	if !ok {
		b, err := json.Marshal(body)
		if err != nil {
			c.t.Fatal(err)
		}
		raw = string(b)
	}
	req := httptest.NewRequest(method, path, strings.NewReader(raw))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	c.mux.ServeHTTP(rec, req)
	var out map[string]any
	if err := json.NewDecoder(bytes.NewReader(rec.Body.Bytes())).Decode(&out); err != nil {
		c.t.Fatalf("%s %s: %d %q is not JSON", method, path, rec.Code, rec.Body.String())
	}
	return rec.Code, out
}

func (c *client) wantError(status int, code string, gotStatus int, body map[string]any) {
	c.t.Helper()
	e, _ := body["error"].(map[string]any)
	if gotStatus != status || e["code"] != code {
		c.t.Fatalf("got %d %v, want %d %s", gotStatus, body, status, code)
	}
}

// session creates a guest and returns its token and player id.
func (c *client) session(nickname string) (string, string) {
	c.t.Helper()
	status, body := c.do("POST", "/v1/sessions", "", map[string]string{"nickname": nickname, "avatarId": "avatar-m04-detective-hat"})
	if status != http.StatusCreated {
		c.t.Fatalf("create session: %d %v", status, body)
	}
	return body["sessionToken"].(string), body["playerId"].(string)
}

func (c *client) createRoom(token string, maxPlayers int) map[string]any {
	c.t.Helper()
	status, body := c.do("POST", "/v1/rooms", token, map[string]any{"maxPlayers": maxPlayers, "hintSeconds": 15, "categoryIds": []string{"animals"}})
	if status != http.StatusCreated {
		c.t.Fatalf("create room: %d %v", status, body)
	}
	return body["room"].(map[string]any)
}

func (c *client) join(token, code string) (int, map[string]any) {
	c.t.Helper()
	return c.do("POST", "/v1/rooms/join", token, map[string]string{"code": code})
}

func players(room map[string]any) []any { return room["players"].([]any) }

func TestSessionValidation(t *testing.T) {
	c := newClient(t)
	cases := []struct {
		name   string
		body   any
		status int
		code   string
	}{
		{"not json", "{", 400, "invalid_message"},
		{"no nickname", map[string]string{"avatarId": "avatar-f01-notebook"}, 422, "invalid_nickname"},
		{"empty nickname", map[string]string{"nickname": "", "avatarId": "avatar-f01-notebook"}, 422, "invalid_nickname"},
		{"one letter after trim", map[string]string{"nickname": "  ד  ", "avatarId": "avatar-f01-notebook"}, 422, "invalid_nickname"},
		{"no avatar", map[string]string{"nickname": "דור"}, 422, "invalid_avatar"},
		{"unknown avatar", map[string]string{"nickname": "דור", "avatarId": "contact-sheet"}, 422, "invalid_avatar"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			status, body := c.do("POST", "/v1/sessions", "", tc.body)
			c.wantError(tc.status, tc.code, status, body)
		})
	}

	token, id := c.session(" דו ")
	if !strings.HasPrefix(id, "p_") || len(token) < 20 {
		t.Fatalf("id %q token %q", id, token)
	}
	if got := c.srv.players[id].nickname; got != "דו" {
		t.Fatalf("nickname stored as %q, want trimmed", got)
	}
}

func TestUpdateSession(t *testing.T) {
	c := newClient(t)
	token, id := c.session("דור")

	status, body := c.do("PATCH", "/v1/sessions/me", "", map[string]string{"nickname": "נועה"})
	c.wantError(401, "session_not_found", status, body)
	status, body = c.do("PATCH", "/v1/sessions/me", "wrong", map[string]string{"nickname": "נועה"})
	c.wantError(401, "session_not_found", status, body)

	// A partly invalid update changes nothing.
	status, body = c.do("PATCH", "/v1/sessions/me", token, map[string]string{"nickname": "נועה", "avatarId": "nope"})
	c.wantError(422, "invalid_avatar", status, body)
	if c.srv.players[id].nickname != "דור" {
		t.Fatal("rejected update was applied")
	}

	status, body = c.do("PATCH", "/v1/sessions/me", token, map[string]string{"avatarId": "avatar-f02-camera"})
	if status != 200 || body["playerId"] != id || c.srv.players[id].avatarID != "avatar-f02-camera" || c.srv.players[id].nickname != "דור" {
		t.Fatalf("got %d %v", status, body)
	}
}

func TestCreateRoom(t *testing.T) {
	c := newClient(t)
	token, id := c.session("דור")

	status, body := c.do("POST", "/v1/rooms", "", map[string]any{"maxPlayers": 8, "hintSeconds": 15, "categoryIds": []string{"a"}})
	c.wantError(401, "session_not_found", status, body)
	for _, bad := range []map[string]any{
		{"maxPlayers": 9, "hintSeconds": 15, "categoryIds": []string{"a"}},
		{"maxPlayers": 8, "hintSeconds": 12, "categoryIds": []string{"a"}},
		{"maxPlayers": 8, "hintSeconds": 15},
	} {
		status, body := c.do("POST", "/v1/rooms", token, bad)
		c.wantError(422, "invalid_room_settings", status, body)
	}

	room := c.createRoom(token, 8)
	p := players(room)[0].(map[string]any)
	switch {
	case !strings.HasPrefix(room["roomId"].(string), "r_"),
		len(room["code"].(string)) != 6,
		room["status"] != "lobby",
		room["hostPlayerId"] != id,
		room["settingsLocked"] != false,
		room["hostTransfer"] != nil,
		room["hostReconnectDeadline"] != nil,
		p["playerId"] != id || p["nickname"] != "דור" || p["avatarId"] != "avatar-m04-detective-hat" || p["connected"] != true,
		p["joinedAt"] != "2026-09-15T12:00:00Z":
		t.Fatalf("room = %v", room)
	}
}

func TestRoomCodesAreUnique(t *testing.T) {
	c := newClient(t)
	codes := []string{"111111", "111111", "111111", "222222"}
	c.srv.newCode = func() string {
		code := codes[0]
		codes = codes[1:]
		return code
	}
	a, _ := c.session("אחד")
	b, _ := c.session("שתיים")
	if c.createRoom(a, 8)["code"] != "111111" || c.createRoom(b, 8)["code"] != "222222" {
		t.Fatal("a code already in use was handed out again")
	}
}

func TestJoinRoom(t *testing.T) {
	c := newClient(t)
	c.srv.newCode = func() string { return "482913" }
	host, _ := c.session("מנהל")
	code := c.createRoom(host, 4)["code"].(string)
	guest, guestID := c.session("אורח")

	status, body := c.join(guest, "12a456")
	c.wantError(422, "invalid_room_code", status, body)
	status, body = c.join(guest, "000000")
	c.wantError(404, "room_not_found", status, body)

	status, body = c.join(guest, code)
	room, _ := body["room"].(map[string]any)
	if status != 200 || len(players(room)) != 2 || room["settingsLocked"] != true || players(room)[1].(map[string]any)["playerId"] != guestID {
		t.Fatalf("join: %d %v", status, body)
	}
	// Joining again returns the same room without adding anyone.
	status, body = c.join(guest, code)
	if status != 200 || len(players(body["room"].(map[string]any))) != 2 {
		t.Fatalf("repeat join: %d %v", status, body)
	}

	for _, name := range []string{"שלוש", "ארבע"} {
		token, _ := c.session(name)
		if status, body := c.join(token, code); status != 200 {
			t.Fatalf("join %s: %d %v", name, status, body)
		}
	}
	fifth, _ := c.session("חמש")
	status, body = c.join(fifth, code)
	c.wantError(409, "room_unavailable", status, body)
}

func TestMovingToAnotherRoomLeavesTheLobby(t *testing.T) {
	c := newClient(t)
	host, hostID := c.session("מנהל")
	first := c.createRoom(host, 8)
	guest, guestID := c.session("אורח")
	if status, _ := c.join(guest, first["code"].(string)); status != 200 {
		t.Fatal("join failed")
	}

	// A failed create keeps the player where they were.
	status, body := c.do("POST", "/v1/rooms", host, map[string]any{"maxPlayers": 2})
	c.wantError(422, "invalid_room_settings", status, body)
	if c.srv.players[hostID].roomID != first["roomId"] {
		t.Fatal("a failed create moved the host out of the room")
	}

	second := c.createRoom(host, 8)
	entry := c.srv.roomsByID[first["roomId"].(string)]
	v := entry.room.View()
	if len(v.Members) != 1 || v.HostID != guestID {
		t.Fatalf("first room after the host moved = %+v", v)
	}
	if c.srv.players[hostID].roomID != second["roomId"] {
		t.Fatal("host is not tracked in the new room")
	}
}

func TestJoiningARoomEveryoneLeftMakesTheJoinerHost(t *testing.T) {
	c := newClient(t)
	host, _ := c.session("מנהל")
	old := c.createRoom(host, 8)
	c.createRoom(host, 8) // the only member moves away

	late, lateID := c.session("מאחר")
	status, body := c.join(late, old["code"].(string))
	room, _ := body["room"].(map[string]any)
	if status != 200 || room["hostPlayerId"] != lateID || len(players(room)) != 1 {
		t.Fatalf("join empty room: %d %v", status, body)
	}
}

func TestCannotMoveRoomsDuringAGame(t *testing.T) {
	c := newClient(t)
	host, hostID := c.session("מנהל")
	room := c.createRoom(host, 8)
	for _, name := range []string{"שתיים", "שלוש", "ארבע"} {
		token, _ := c.session(name)
		c.join(token, room["code"].(string))
	}
	entry := c.srv.roomsByID[room["roomId"].(string)]
	if err := entry.room.Start(hostID, "animals", "פיל", t0); err != nil {
		t.Fatal(err)
	}

	other, _ := c.session("אחר")
	otherCode := c.createRoom(other, 8)["code"].(string)
	status, body := c.join(host, otherCode)
	c.wantError(409, "already_in_activity", status, body)
	status, body = c.do("POST", "/v1/rooms", host, map[string]any{"maxPlayers": 8, "hintSeconds": 15, "categoryIds": []string{"a"}})
	c.wantError(409, "already_in_activity", status, body)
	if len(entry.room.View().Members) != 4 {
		t.Fatal("a refused move changed the room")
	}

	// Joining a room that is in a game is refused as unavailable.
	late, _ := c.session("מאחר")
	status, body = c.join(late, room["code"].(string))
	c.wantError(409, "room_unavailable", status, body)
}

func TestKickedPlayerCanMoveEvenIfTheOldRoomStarted(t *testing.T) {
	c := newClient(t)
	host, hostID := c.session("מנהל")
	room := c.createRoom(host, 8)
	kicked, kickedID := c.session("מוסר")
	c.join(kicked, room["code"].(string))
	for _, name := range []string{"שתיים", "שלוש", "ארבע"} {
		token, _ := c.session(name)
		c.join(token, room["code"].(string))
	}
	entry := c.srv.roomsByID[room["roomId"].(string)]
	if err := entry.room.Kick(hostID, kickedID, t0); err != nil {
		t.Fatal(err)
	}
	if err := entry.room.Start(hostID, "animals", "פיל", t0); err != nil {
		t.Fatal(err)
	}
	c.createRoom(kicked, 8)
}

func TestBodyLimit(t *testing.T) {
	c := newClient(t)
	status, body := c.do("POST", "/v1/sessions", "", `{"nickname":"`+strings.Repeat("א", maxBodyBytes)+`","avatarId":"avatar-f01-notebook"}`)
	c.wantError(400, "invalid_message", status, body)
}
