package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/coder/websocket"

	"github.com/dorohayon/Imposter-IL/server/internal/content"
	"github.com/dorohayon/Imposter-IL/server/internal/room"
)

// WebSocket part of docs/protocol.md: private rooms, online matchmaking and
// the games played in both.

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
		s.metrics.wsConns--
		s.detach(sess, c)
		s.mu.Unlock()
	}()

	s.mu.Lock()
	s.metrics.wsConns++
	sess.lastSeen, sess.connected = s.now(), true
	s.attach(sess, c)
	interval := s.pingInterval
	s.mu.Unlock()
	s.safely("writeLoop", func() { s.writeLoop(c) })
	s.safely("pingLoop", func() { pingLoop(c, interval) })
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
		sess.lastSeen = now
		msg, ok := sess.replies.get(env.ID, now)
		switch {
		case ok:
			// Replayed message id: the cached reply, command not run again.
		case !s.commandLimit.allow(sess.playerID, now):
			s.metrics.rateLimited++
			s.countCommand("rate_limited")
			msg = reply(env.ID, "rate_limited", now)
			sess.replies.put(env.ID, msg, now)
		default:
			code := s.dispatchSafe(sess, env, now)
			s.countCommand(code)
			msg = reply(env.ID, code, now)
			sess.replies.put(env.ID, msg, now)
		}
		s.queue(c, msg)
		s.syncSession(sess)
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
	if sess.game != nil && (sess.gameRoom != entry || sess.game != entry.room.Game()) {
		// A game the player was removed from, or an earlier game of the room.
		entry := sess.gameRoom
		entry.stateVersion++
		s.sendGameState(sess, entry.stateVersion, s.now())
	}
}

// detach records a real disconnect, unless c was already replaced.
func (s *Server) detach(sess *session, c *conn) {
	if sess.conn != c {
		return
	}
	sess.conn = nil
	if entry := s.currentRoom(sess); entry != nil {
		if s.searching(entry) {
			s.leaveSearch(sess, entry, s.now()) // closing the app cancels a search
		} else {
			_ = entry.room.Disconnect(sess.playerID, s.now())
		}
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
	switch {
	case sess.gameID != "":
		payload["activity"], payload["roomId"], payload["gameId"] = "game", sess.gameRoom.id, sess.gameID
	case sess.roomID != "":
		payload["activity"], payload["roomId"] = "room", sess.roomID
		if entry := s.roomsByID[sess.roomID]; entry != nil && entry.public {
			payload["activity"] = "matchmaking"
		}
	}
	s.queue(sess.conn, message("session.state", s.now(), payload))
}

// publish sends room.state to every connected member, game.state to every
// player showing the room's game, and reschedules the room's timer. Call it
// after anything that may change the room or its game.
func (s *Server) publish(entry *roomEntry) {
	defer s.timePublish(time.Now())
	now := s.now()
	s.settleFinishedMatch(entry, now)
	v := entry.room.View()
	entry.stateVersion++
	entry.published = mark(entry)
	switch {
	case s.searching(entry):
		s.publishSearch(entry, now)
	case !entry.public:
		msg := message("room.state", now, map[string]any{"stateVersion": entry.stateVersion, "room": s.roomJSON(entry)})
		for _, m := range v.Members {
			if sess := s.players[m.ID]; sess != nil {
				s.queue(sess.conn, msg)
			}
		}
	}
	s.publishGame(entry, now)
	s.schedule(entry)
}

func (s *Server) schedule(entry *roomEntry) {
	if entry.timer != nil {
		entry.timer.Stop()
		entry.timer = nil
	}
	deadline := entry.room.Deadline()
	if search := s.searchDeadline(entry); !search.IsZero() && (deadline.IsZero() || search.Before(deadline)) {
		deadline = search
	}
	if deadline.IsZero() {
		return
	}
	entry.timer = time.AfterFunc(max(deadline.Sub(s.now()), 0), func() {
		s.mu.Lock()
		defer s.mu.Unlock()
		// Runs before the unlock above, so it still holds the lock it needs.
		defer s.recoverRoom(entry, "timer")
		s.tickRoom(entry)
	})
}

// tickRoom applies the room's and its game's deadlines. A timer that was
// stopped too late to cancel simply finds nothing due.
func (s *Server) tickRoom(entry *roomEntry) {
	now := s.now()
	entry.room.Tick(now)
	s.tickSearch(entry, now)
	s.sync(entry)
}

func mark(entry *roomEntry) snapshotMark {
	m := snapshotMark{roomVersion: entry.room.View().Version, lobbyVersion: entry.lobbyVersion, game: entry.room.Game()}
	if m.game != nil {
		m.gameVersion = m.game.Version()
	}
	return m
}

// sync publishes the room if it or its game changed since the last snapshot,
// and otherwise only reschedules its timer. Room and game methods apply
// expired deadlines before running, so any call can advance the state even
// when the call itself fails.
func (s *Server) sync(entry *roomEntry) {
	s.settleFinishedMatch(entry, s.now())
	if mark(entry) != entry.published {
		s.publish(entry)
		return
	}
	s.schedule(entry)
}

// syncSession syncs the rooms a session's last request may have touched.
func (s *Server) syncSession(sess *session) {
	if entry := s.roomsByID[sess.roomID]; entry != nil {
		s.sync(entry)
	}
	if sess.gameRoom != nil && sess.gameRoom.id != sess.roomID {
		s.sync(sess.gameRoom)
	}
}

// dispatchSafe runs a command so that a panic costs the player's room rather
// than the process and every other game on it. The player gets internal_error.
func (s *Server) dispatchSafe(sess *session, env envelope, now time.Time) (code string) {
	entry := s.roomsByID[sess.roomID]
	if entry == nil {
		entry = sess.gameRoom
	}
	defer func() {
		if r := recover(); r != nil {
			s.panicked("command "+env.Type, r)
			if entry != nil {
				s.abortRoom(entry)
			}
			code = "internal_error"
		}
	}()
	return s.dispatch(sess, env, now)
}

// dispatch runs one client command and returns its error code, or "" on success.
func (s *Server) dispatch(sess *session, env envelope, now time.Time) string {
	var p commandPayload
	if len(env.Payload) > 0 && json.Unmarshal(env.Payload, &p) != nil {
		return "invalid_message"
	}
	switch {
	case strings.HasPrefix(env.Type, "room."):
		return s.roomCommand(sess, env.Type, p, now)
	case strings.HasPrefix(env.Type, "game."):
		return s.gameCommand(sess, env.Type, p, now)
	case strings.HasPrefix(env.Type, "matchmaking."):
		return s.matchmakingCommand(sess, env.Type, p, now)
	}
	return "invalid_message"
}

// commandPayload holds the fields of every room.* and game.* payload.
type commandPayload struct {
	RoomID         string `json:"roomId"`
	GameID         string `json:"gameId"`
	PlayerID       string `json:"playerId"`
	TargetPlayerID string `json:"targetPlayerId"`
	Text           string `json:"text"`
	HintIndex      *int   `json:"hintIndex"`
	ReactionID     string `json:"reactionId"`
	settingsRequest
}

func (s *Server) roomCommand(sess *session, typ string, p commandPayload, now time.Time) string {
	switch typ {
	case "room.updateSettings", "room.kick", "room.start", "room.leave":
	default:
		return "invalid_message"
	}
	entry := s.currentRoom(sess)
	if entry == nil || entry.id != p.RoomID || entry.public {
		return "room_not_found" // online matches have no room commands
	}

	var err error
	switch typ {
	case "room.updateSettings":
		if !content.ValidIDs(p.CategoryIDs) {
			return "invalid_room_settings"
		}
		err = entry.room.UpdateSettings(sess.playerID, room.Settings{MaxPlayers: p.MaxPlayers, HintSeconds: p.HintSeconds, CategoryIDs: p.CategoryIDs}, now)
	case "room.kick":
		if err = entry.room.Kick(sess.playerID, p.PlayerID, now); err == nil {
			if kicked := s.players[p.PlayerID]; kicked != nil {
				kicked.roomID = ""
				kicked.leaveGame()
				s.queue(kicked.conn, message("room.kicked", now, map[string]string{"roomId": entry.id}))
				s.sendSessionState(kicked)
			}
		}
	case "room.start":
		if s.draining {
			return "server_draining"
		}
		return s.startGame(sess, entry, now)
	case "room.leave":
		if err = entry.room.Leave(sess.playerID, now); err == nil {
			sess.roomID = ""
			sess.leaveGame()
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
		room.ErrNotHost:          "not_room_host",
		room.ErrSettingsLocked:   "room_settings_locked",
		room.ErrInvalidSettings:  "invalid_room_settings",
		room.ErrCannotKickSelf:   "cannot_kick_self",
		room.ErrNotEnoughPlayers: "not_enough_players",
		room.ErrInGame:           "room_in_game",
		room.ErrUnknownPlayer:    "unknown_player",
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
