package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

type wsClient struct {
	t       *testing.T
	ws      *websocket.Conn
	skipped []map[string]any // read while waiting for another type
}

func (c *client) dial(token string) *wsClient {
	c.t.Helper()
	ws, resp, err := c.dialRaw(token)
	if err != nil {
		c.t.Fatalf("dial: %v (%v)", err, resp)
	}
	w := &wsClient{t: c.t, ws: ws}
	c.t.Cleanup(func() { _ = ws.CloseNow() })
	return w
}

func (c *client) dialRaw(token string) (*websocket.Conn, *http.Response, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	header := http.Header{}
	if token != "" {
		header.Set("Authorization", "Bearer "+token)
	}
	return websocket.Dial(ctx, "ws"+strings.TrimPrefix(c.ts.URL, "http")+"/v1/ws", &websocket.DialOptions{HTTPHeader: header})
}

func (w *wsClient) send(msg any) {
	w.t.Helper()
	raw, ok := msg.(string)
	if !ok {
		b, _ := json.Marshal(msg)
		raw = string(b)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := w.ws.Write(ctx, websocket.MessageText, []byte(raw)); err != nil {
		w.t.Fatal(err)
	}
}

func (w *wsClient) command(id, typ string, payload any) map[string]any {
	w.t.Helper()
	w.send(map[string]any{"v": 1, "id": id, "type": typ, "payload": payload})
	return w.reply(id)
}

// next returns the oldest unseen message of type typ. Messages of other types
// are kept for later calls.
func (w *wsClient) next(typ string) map[string]any {
	w.t.Helper()
	for i, msg := range w.skipped {
		if msg["type"] == typ {
			w.skipped = append(w.skipped[:i], w.skipped[i+1:]...)
			return msg
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	for {
		_, data, err := w.ws.Read(ctx)
		if err != nil {
			w.t.Fatalf("waiting for %s: %v", typ, err)
		}
		var msg map[string]any
		if err := json.Unmarshal(data, &msg); err != nil {
			w.t.Fatal(err)
		}
		if msg["type"] == typ {
			return msg
		}
		w.skipped = append(w.skipped, msg)
	}
}

func (w *wsClient) reply(id string) map[string]any {
	w.t.Helper()
	for {
		if msg := w.next("reply"); msg["replyTo"] == id {
			return msg
		}
	}
}

// roomState waits for a room.state that satisfies ok.
func (w *wsClient) roomState(ok func(room map[string]any) bool) map[string]any {
	w.t.Helper()
	for {
		payload := w.next("room.state")["payload"].(map[string]any)
		if room := payload["room"].(map[string]any); ok(room) {
			return room
		}
	}
}

// sessionState waits for a session.state that satisfies ok.
func (w *wsClient) sessionState(ok func(payload map[string]any) bool) map[string]any {
	w.t.Helper()
	for {
		if payload := w.next("session.state")["payload"].(map[string]any); ok(payload) {
			return payload
		}
	}
}

func wantReplyError(t *testing.T, msg map[string]any, code string) {
	t.Helper()
	e, _ := msg["error"].(map[string]any)
	if msg["ok"] != false || e["code"] != code {
		t.Fatalf("reply = %v, want error %s", msg, code)
	}
}

func wantOK(t *testing.T, msg map[string]any) {
	t.Helper()
	if msg["ok"] != true {
		t.Fatalf("reply = %v, want ok", msg)
	}
}

func member(room map[string]any, id string) map[string]any {
	for _, p := range players(room) {
		if p := p.(map[string]any); p["playerId"] == id {
			return p
		}
	}
	return nil
}

func TestWSRequiresSession(t *testing.T) {
	c := newClient(t)
	for _, token := range []string{"", "wrong"} {
		_, resp, err := c.dialRaw(token)
		if err == nil || resp == nil || resp.StatusCode != http.StatusUnauthorized {
			t.Fatalf("token %q: err %v resp %v", token, err, resp)
		}
	}
}

func TestWSConnectSendsSessionThenRoomState(t *testing.T) {
	c := newClient(t)
	token, id := c.session("דור")
	w := c.dial(token)
	if p := w.next("session.state")["payload"].(map[string]any); p["playerId"] != id || p["activity"] != "none" {
		t.Fatalf("session.state = %v", p)
	}

	room := c.createRoom(token, 8)
	if p := w.next("session.state")["payload"].(map[string]any); p["activity"] != "room" || p["roomId"] != room["roomId"] {
		t.Fatalf("session.state after create = %v", p)
	}
	msg := w.next("room.state")
	if msg["serverTime"] != "2026-09-15T12:00:00Z" || msg["payload"].(map[string]any)["stateVersion"] == nil {
		t.Fatalf("room.state = %v", msg)
	}

	// Reconnecting sends the session first, then the room snapshot.
	_ = w.ws.Close(websocket.StatusNormalClosure, "")
	again := c.dial(token)
	if p := again.next("session.state")["payload"].(map[string]any); p["activity"] != "room" {
		t.Fatalf("session.state on reconnect = %v", p)
	}
	again.roomState(func(r map[string]any) bool { return member(r, id)["connected"] == true })
}

func TestWSEnvelopeErrors(t *testing.T) {
	c := newClient(t)
	token, _ := c.session("דור")
	w := c.dial(token)

	w.send("{")
	wantReplyError(t, w.next("reply"), "invalid_message")
	w.send(map[string]any{"v": 1, "type": "room.leave"}) // no id
	wantReplyError(t, w.next("reply"), "invalid_message")
	wantReplyError(t, w.command("m1", "lobby.dance", map[string]any{}), "invalid_message")
	wantReplyError(t, w.command("m2", "room.leave", map[string]any{"roomId": "r_x"}), "room_not_found")

	w.send(map[string]any{"v": 2, "id": "m3", "type": "room.leave"})
	wantReplyError(t, w.reply("m3"), "unsupported_protocol_version")
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if _, _, err := w.ws.Read(ctx); websocket.CloseStatus(err) != websocket.StatusPolicyViolation {
		t.Fatalf("connection not closed for an unsupported version: %v", err)
	}
}

func TestWSRepeatedMessageIDGetsTheSameReplyWithoutRunningAgain(t *testing.T) {
	c := newClient(t)
	token, _ := c.session("דור")
	room := c.createRoom(token, 8)
	w := c.dial(token)
	settings := func(hint int) map[string]any {
		return map[string]any{"roomId": room["roomId"], "maxPlayers": 8, "hintSeconds": hint, "categoryIds": []string{"animals"}}
	}

	bad := settings(10)
	bad["categoryIds"] = []string{"cars"}
	wantReplyError(t, w.command("bad", "room.updateSettings", bad), "invalid_room_settings")

	first := w.command("same", "room.updateSettings", settings(10))
	wantOK(t, first)
	second := w.command("same", "room.updateSettings", settings(20))
	if second["serverTime"] != first["serverTime"] || second["ok"] != true {
		t.Fatalf("second reply = %v, want the cached %v", second, first)
	}
	entry := c.srv.roomsByID[room["roomId"].(string)]
	c.srv.mu.Lock()
	hint := entry.room.View().Settings.HintSeconds
	c.srv.mu.Unlock()
	if hint != 10 {
		t.Fatalf("hint seconds = %d, the repeated message ran again", hint)
	}

	// After five minutes the id is forgotten.
	c.advance(replyCacheTTL)
	wantOK(t, w.command("same", "room.updateSettings", settings(20)))
}

func TestWSKickAndLeave(t *testing.T) {
	c := newClient(t)
	hostToken, _ := c.session("מנהל")
	room := c.createRoom(hostToken, 8)
	roomID, code := room["roomId"], room["code"].(string)
	guestToken, guestID := c.session("אורח")
	c.join(guestToken, code)
	host, guest := c.dial(hostToken), c.dial(guestToken)
	host.roomState(func(r map[string]any) bool { return len(players(r)) == 2 })

	wantReplyError(t, guest.command("g1", "room.kick", map[string]any{"roomId": roomID, "playerId": guestID}), "not_room_host")
	wantReplyError(t, host.command("h1", "room.kick", map[string]any{"roomId": roomID, "playerId": "p_nobody"}), "unknown_player")
	wantOK(t, host.command("h2", "room.kick", map[string]any{"roomId": roomID, "playerId": guestID}))
	if p := guest.next("room.kicked")["payload"].(map[string]any); p["roomId"] != roomID {
		t.Fatalf("room.kicked = %v", p)
	}
	guest.sessionState(func(p map[string]any) bool { return p["activity"] == "none" })
	host.roomState(func(r map[string]any) bool { return len(players(r)) == 1 })

	// A removed player may rejoin, and the host sees it live.
	if status, body := c.join(guestToken, code); status != 200 {
		t.Fatalf("rejoin: %d %v", status, body)
	}
	host.roomState(func(r map[string]any) bool { return member(r, guestID) != nil })

	wantOK(t, guest.command("g2", "room.leave", map[string]any{"roomId": roomID}))
	guest.sessionState(func(p map[string]any) bool { return p["activity"] == "none" })
	host.roomState(func(r map[string]any) bool { return member(r, guestID) == nil })
}

func TestWSDisconnectAndHostTimeout(t *testing.T) {
	c := newClient(t)
	hostToken, hostID := c.session("מנהל")
	room := c.createRoom(hostToken, 8)
	guestToken, guestID := c.session("אורח")
	c.join(guestToken, room["code"].(string))
	host, guest := c.dial(hostToken), c.dial(guestToken)
	host.roomState(func(r map[string]any) bool { return len(players(r)) == 2 })

	_ = host.ws.Close(websocket.StatusNormalClosure, "")
	r := guest.roomState(func(r map[string]any) bool { return member(r, hostID)["connected"] == false })
	if r["hostReconnectDeadline"] != "2026-09-15T12:00:30Z" {
		t.Fatalf("room after the host disconnected = %v", r)
	}
	entry := c.srv.roomsByID[room["roomId"].(string)]
	c.srv.mu.Lock()
	scheduled := entry.timer != nil
	c.srv.mu.Unlock()
	if !scheduled {
		t.Fatal("no timer for the host deadline")
	}

	c.advance(30 * time.Second)
	c.srv.mu.Lock()
	c.srv.tickRoom(entry)
	c.srv.mu.Unlock()
	r = guest.roomState(func(r map[string]any) bool { return r["hostPlayerId"] == guestID })
	if tr := r["hostTransfer"].(map[string]any); tr["reason"] != "host_timeout" || tr["fromPlayerId"] != hostID {
		t.Fatalf("transfer = %v", tr)
	}
}

func TestWSNewConnectionReplacesTheOldOneWithoutADisconnect(t *testing.T) {
	c := newClient(t)
	token, id := c.session("מנהל")
	room := c.createRoom(token, 8)
	old := c.dial(token)
	old.next("session.state")
	c.dial(token).next("room.state")

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	for {
		if _, _, err := old.ws.Read(ctx); err != nil {
			if errors.Is(err, context.DeadlineExceeded) {
				t.Fatal("old connection stayed open")
			}
			break
		}
	}
	entry := c.srv.roomsByID[room["roomId"].(string)]
	c.srv.mu.Lock()
	defer c.srv.mu.Unlock()
	if v := entry.room.View(); !v.Members[0].Connected || v.HostID != id || !v.HostReconnectDeadline.IsZero() {
		t.Fatalf("replacing the connection counted as a disconnect: %+v", v)
	}
}

func TestWSMissedPongsDisconnect(t *testing.T) {
	c := newClient(t)
	c.srv.mu.Lock()
	c.srv.pingInterval = 20 * time.Millisecond
	c.srv.mu.Unlock()
	hostToken, _ := c.session("מנהל")
	room := c.createRoom(hostToken, 8)
	silentToken, silentID := c.session("שקט")
	c.join(silentToken, room["code"].(string))
	host := c.dial(hostToken)
	c.dial(silentToken) // never reads, so pongs are never processed

	host.roomState(func(r map[string]any) bool { return member(r, silentID)["connected"] == false })
}

func TestWSProfileChangeRaisesTheStateVersion(t *testing.T) {
	c := newClient(t)
	token, id := c.session("דור")
	c.createRoom(token, 8)
	w := c.dial(token)
	w.next("session.state")
	before := w.next("room.state")["payload"].(map[string]any)["stateVersion"].(float64)

	if status, body := c.do("PATCH", "/v1/sessions/me", token, map[string]string{"nickname": "נועה"}); status != 200 {
		t.Fatalf("patch: %d %v", status, body)
	}
	for {
		payload := w.next("room.state")["payload"].(map[string]any)
		if member(payload["room"].(map[string]any), id)["nickname"] == "נועה" {
			if payload["stateVersion"].(float64) <= before {
				t.Fatalf("stateVersion %v did not rise above %v", payload["stateVersion"], before)
			}
			return
		}
	}
}
