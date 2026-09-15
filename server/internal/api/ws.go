package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/coder/websocket"

	"github.com/dorohayon/Imposter-IL/server/internal/room"
)

// WebSocket part of docs/protocol.md for private room lobbies. Game messages
// arrive in the next step and are rejected as invalid_message until then.

const (
	protocolVersion = 1
	sendBuffer      = 64
	writeTimeout    = 10 * time.Second
	replyCacheSize  = 100
	replyCacheTTL   = 5 * time.Minute
)

type conn struct {
	ws     *websocket.Conn
	send   chan []byte
	ctx    context.Context
	cancel context.CancelFunc
}

// queue hands a message to the connection's writer without blocking under the
// server lock. A client too slow to keep up is disconnected.
func (s *Server) queue(c *conn, msg []byte) {
	if c == nil {
		return
	}
	select {
	case c.send <- msg:
	default:
		c.cancel()
	}
}

func (s *Server) serveWS(w http.ResponseWriter, r *http.Request) {
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	s.mu.Lock()
	sess := s.sessions[token]
	s.mu.Unlock()
	if !ok || sess == nil {
		writeError(w, errSessionNotFound)
		return
	}
	ws, err := websocket.Accept(w, r, nil)
	if err != nil {
		return
	}
	ws.SetReadLimit(maxBodyBytes)
	ctx, cancel := context.WithCancel(context.Background())
	c := &conn{ws: ws, send: make(chan []byte, sendBuffer), ctx: ctx, cancel: cancel}
	defer func() {
		cancel()
		_ = ws.CloseNow()
		s.mu.Lock()
		s.detach(sess, c)
		s.mu.Unlock()
	}()

	s.mu.Lock()
	s.attach(sess, c)
	interval := s.pingInterval
	s.mu.Unlock()
	go s.writeLoop(c)
	go pingLoop(c, interval)
	s.readLoop(sess, c)
}

func (*Server) writeLoop(c *conn) {
	for {
		select {
		case <-c.ctx.Done():
			return
		case msg := <-c.send:
			ctx, cancel := context.WithTimeout(c.ctx, writeTimeout)
			err := c.ws.Write(ctx, websocket.MessageText, msg)
			cancel()
			if err != nil {
				c.cancel()
				return
			}
		}
	}
}

// pingLoop pings every interval. A pong missing for two intervals counts as a
// disconnect, the protocol's "two missed pongs".
func pingLoop(c *conn, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-c.ctx.Done():
			return
		case <-ticker.C:
			ctx, cancel := context.WithTimeout(c.ctx, 2*interval)
			err := c.ws.Ping(ctx)
			cancel()
			if err != nil {
				c.cancel()
				return
			}
		}
	}
}

type envelope struct {
	V       int             `json:"v"`
	ID      string          `json:"id"`
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

func (s *Server) readLoop(sess *session, c *conn) {
	for {
		_, data, err := c.ws.Read(c.ctx)
		if err != nil {
			return
		}
		var env envelope
		if json.Unmarshal(data, &env) != nil || env.ID == "" || env.Type == "" {
			s.queue(c, reply(env.ID, "invalid_message", time.Now()))
			continue
		}
		if env.V != protocolVersion {
			ctx, cancel := context.WithTimeout(c.ctx, writeTimeout)
			_ = c.ws.Write(ctx, websocket.MessageText, reply(env.ID, "unsupported_protocol_version", time.Now()))
			cancel()
			_ = c.ws.Close(websocket.StatusPolicyViolation, "unsupported protocol version")
			return
		}
		s.mu.Lock()
		now := s.now()
		msg, ok := sess.replies.get(env.ID, now)
		if !ok {
			msg = reply(env.ID, s.dispatch(sess, env, now), now)
			sess.replies.put(env.ID, msg, now)
		}
		s.queue(c, msg)
		s.mu.Unlock()
	}
}

// attach makes c the session's connection, replacing an older one without
// counting a disconnect, then sends session.state and the room snapshot.
func (s *Server) attach(sess *session, c *conn) {
	if old := sess.conn; old != nil {
		old.cancel()
		go func() { _ = old.ws.Close(websocket.StatusPolicyViolation, "replaced by a new connection") }()
	}
	sess.conn = c
	entry := s.currentRoom(sess)
	s.sendSessionState(sess)
	if entry != nil {
		_ = entry.room.Reconnect(sess.playerID, s.now())
		s.publish(entry)
	}
}

// detach records a real disconnect, unless c was already replaced.
func (s *Server) detach(sess *session, c *conn) {
	if sess.conn != c {
		return
	}
	sess.conn = nil
	if entry := s.currentRoom(sess); entry != nil {
		_ = entry.room.Disconnect(sess.playerID, s.now())
		s.publish(entry)
	}
}

func message(typ string, now time.Time, payload any) []byte {
	b, _ := json.Marshal(map[string]any{"v": protocolVersion, "type": typ, "serverTime": now.UTC(), "payload": payload})
	return b
}

func reply(id, code string, now time.Time) []byte {
	msg := map[string]any{"v": protocolVersion, "type": "reply", "replyTo": id, "serverTime": now.UTC(), "ok": code == ""}
	if code != "" {
		msg["error"] = map[string]string{"code": code}
	}
	b, _ := json.Marshal(msg)
	return b
}

func (s *Server) sendSessionState(sess *session) {
	payload := map[string]any{"playerId": sess.playerID, "activity": "none"}
	if sess.roomID != "" {
		payload["activity"], payload["roomId"] = "room", sess.roomID
	}
	s.queue(sess.conn, message("session.state", s.now(), payload))
}

// publish sends room.state to every connected member and reschedules the
// room's timer. Call it after anything that may change the room.
func (s *Server) publish(entry *roomEntry) {
	v := entry.room.View()
	msg := message("room.state", s.now(), map[string]any{"stateVersion": v.Version, "room": s.roomJSON(entry)})
	for _, m := range v.Members {
		if sess := s.players[m.ID]; sess != nil {
			s.queue(sess.conn, msg)
		}
	}
	s.schedule(entry)
}

func (s *Server) schedule(entry *roomEntry) {
	if entry.timer != nil {
		entry.timer.Stop()
		entry.timer = nil
	}
	deadline := entry.room.Deadline()
	if deadline.IsZero() {
		return
	}
	entry.timer = time.AfterFunc(max(deadline.Sub(s.now()), 0), func() {
		s.mu.Lock()
		defer s.mu.Unlock()
		s.tickRoom(entry)
	})
}

// tickRoom applies the room's deadlines. A timer that was stopped too late to
// cancel simply finds nothing due.
func (s *Server) tickRoom(entry *roomEntry) {
	before := entry.room.View().Version
	entry.room.Tick(s.now())
	if entry.room.View().Version != before {
		s.publish(entry)
		return
	}
	s.schedule(entry)
}

// dispatch runs one client command and returns its error code, or "" on success.
func (s *Server) dispatch(sess *session, env envelope, now time.Time) string {
	var p struct {
		RoomID   string `json:"roomId"`
		PlayerID string `json:"playerId"`
		settingsRequest
	}
	if len(env.Payload) > 0 && json.Unmarshal(env.Payload, &p) != nil {
		return "invalid_message"
	}
	switch env.Type {
	case "room.updateSettings", "room.kick", "room.leave":
	default:
		return "invalid_message"
	}
	entry := s.currentRoom(sess)
	if entry == nil || entry.id != p.RoomID {
		return "room_not_found"
	}

	var err error
	switch env.Type {
	case "room.updateSettings":
		err = entry.room.UpdateSettings(sess.playerID, room.Settings{MaxPlayers: p.MaxPlayers, HintSeconds: p.HintSeconds, CategoryIDs: p.CategoryIDs}, now)
	case "room.kick":
		if err = entry.room.Kick(sess.playerID, p.PlayerID, now); err == nil {
			if kicked := s.players[p.PlayerID]; kicked != nil {
				kicked.roomID = ""
				s.queue(kicked.conn, message("room.kicked", now, map[string]string{"roomId": entry.id}))
				s.sendSessionState(kicked)
			}
		}
	case "room.leave":
		if err = entry.room.Leave(sess.playerID, now); err == nil {
			sess.roomID = ""
			s.sendSessionState(sess)
		}
	}
	if err != nil {
		return roomErrorCode(err)
	}
	s.publish(entry)
	return ""
}

func roomErrorCode(err error) string {
	for target, code := range map[error]string{
		room.ErrNotHost:         "not_room_host",
		room.ErrSettingsLocked:  "room_settings_locked",
		room.ErrInvalidSettings: "invalid_room_settings",
		room.ErrCannotKickSelf:  "cannot_kick_self",
		room.ErrInGame:          "room_in_game",
		room.ErrUnknownPlayer:   "unknown_player",
	} {
		if errors.Is(err, target) {
			return code
		}
	}
	return "internal_error"
}

// replyCache keeps recent replies so a repeated message id gets the same
// answer without running the command again.
type replyCache struct {
	byID  map[string]cachedReply
	order []cachedID
}

type cachedReply struct {
	at  time.Time
	msg []byte
}

type cachedID struct {
	id string
	at time.Time
}

func (c *replyCache) get(id string, now time.Time) ([]byte, bool) {
	r, ok := c.byID[id]
	return r.msg, ok && now.Sub(r.at) < replyCacheTTL
}

func (c *replyCache) put(id string, msg []byte, now time.Time) {
	if c.byID == nil {
		c.byID = map[string]cachedReply{}
	}
	c.byID[id] = cachedReply{at: now, msg: msg}
	c.order = append(c.order, cachedID{id: id, at: now})
	for len(c.order) > 0 && (len(c.order) > replyCacheSize || now.Sub(c.order[0].at) >= replyCacheTTL) {
		oldest := c.order[0]
		if c.byID[oldest.id].at.Equal(oldest.at) { // not overwritten by a later use of the id
			delete(c.byID, oldest.id)
		}
		c.order = c.order[1:]
	}
}
