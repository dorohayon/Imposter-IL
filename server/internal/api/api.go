// Package api serves docs/protocol.md over REST and WebSocket: guest sessions
// and private rooms. All state lives in memory, as the MVP architecture
// requires.
package api

import (
	crand "crypto/rand"
	"encoding/json"
	"errors"
	"io"
	"math/rand/v2"
	"net/http"
	"slices"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
	"github.com/dorohayon/Imposter-IL/server/internal/room"
)

// MinNicknameRunes is the approved minimum after trimming. The maximum length
// and allowed characters are still open decisions.
const MinNicknameRunes = 2

const maxBodyBytes = 64 << 10

// AvatarIDs are the file names under assets/avatars without the extension.
var AvatarIDs = []string{
	"avatar-f01-notebook", "avatar-f02-camera", "avatar-f03-headphones",
	"avatar-f04-map", "avatar-f05-fingerprint-kit", "avatar-f06-laptop",
	"avatar-m01-flashlight", "avatar-m02-binoculars", "avatar-m03-evidence-bag",
	"avatar-m04-detective-hat", "avatar-m05-badge", "avatar-m06-magnifying-glass",
}

type session struct {
	playerID string
	nickname string
	avatarID string
	roomID   string // current private room, if any

	conn    *conn // current WebSocket, if connected
	replies replyCache
}

type roomEntry struct {
	id    string
	room  *room.Room
	timer *time.Timer // fires at room.Deadline()
}

// Server holds sessions, rooms and connections.
// ponytail: one lock for everything, including room timers; move each room
// into its own actor goroutine if lock contention shows up.
type Server struct {
	now          func() time.Time
	policy       game.Policy
	newCode      func() string
	pingInterval time.Duration

	mu        sync.Mutex
	rng       *rand.Rand
	sessions  map[string]*session // token -> session
	players   map[string]*session // player id -> session
	roomsByID map[string]*roomEntry
	roomsCode map[string]*roomEntry
}

// NewServer uses policy for games started in rooms. The content rules are
// still open, so an incomplete policy makes game start fail rather than
// silently apply a placeholder.
func NewServer(now func() time.Time, policy game.Policy) *Server {
	var seed [32]byte
	_, _ = crand.Read(seed[:])
	s := &Server{
		now:          now,
		policy:       policy,
		pingInterval: 10 * time.Second,
		rng:          rand.New(rand.NewChaCha8(seed)),
		sessions:     map[string]*session{},
		players:      map[string]*session{},
		roomsByID:    map[string]*roomEntry{},
		roomsCode:    map[string]*roomEntry{},
	}
	s.newCode = func() string { return room.NewCode(s.rng) }
	return s
}

func (s *Server) Routes(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/sessions", s.createSession)
	mux.HandleFunc("PATCH /v1/sessions/me", s.withSession(s.updateSession))
	mux.HandleFunc("POST /v1/rooms", s.withSession(s.createRoom))
	mux.HandleFunc("POST /v1/rooms/join", s.withSession(s.joinRoom))
	mux.HandleFunc("GET /v1/ws", s.serveWS)
}

type apiError struct {
	status  int
	code    string
	message string
}

var (
	errInvalidMessage  = apiError{http.StatusBadRequest, "invalid_message", "invalid request body"}
	errSessionNotFound = apiError{http.StatusUnauthorized, "session_not_found", "session not found"}
	errInvalidNickname = apiError{http.StatusUnprocessableEntity, "invalid_nickname", "nickname must have at least 2 characters"}
	errInvalidAvatar   = apiError{http.StatusUnprocessableEntity, "invalid_avatar", "unknown avatar"}
	errInvalidSettings = apiError{http.StatusUnprocessableEntity, "invalid_room_settings", "invalid room settings"}
	errInvalidRoomCode = apiError{http.StatusUnprocessableEntity, "invalid_room_code", "room code must be six digits"}
	errRoomNotFound    = apiError{http.StatusNotFound, "room_not_found", "room not found"}
	errRoomUnavailable = apiError{http.StatusConflict, "room_unavailable", "room is full or in a game"}
	errAlreadyInGame   = apiError{http.StatusConflict, "already_in_activity", "leave the current game first"}
	errInternal        = apiError{http.StatusInternalServerError, "internal_error", "internal error"}
)

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, e apiError) {
	writeJSON(w, e.status, map[string]any{"error": map[string]string{"code": e.code, "message": e.message}})
}

// readBody reads the whole body before any lock is taken, so a slow client
// cannot hold up other requests.
func readBody(w http.ResponseWriter, r *http.Request) ([]byte, bool) {
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		writeError(w, errInvalidMessage)
		return nil, false
	}
	return body, true
}

func decode(w http.ResponseWriter, body []byte, dst any) bool {
	if err := json.Unmarshal(body, dst); err != nil {
		writeError(w, errInvalidMessage)
		return false
	}
	return true
}

func (s *Server) withSession(next func(http.ResponseWriter, []byte, *session)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		body, ok := readBody(w, r)
		if !ok {
			return
		}
		token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		s.mu.Lock()
		defer s.mu.Unlock()
		sess := s.sessions[token]
		if !ok || sess == nil {
			writeError(w, errSessionNotFound)
			return
		}
		next(w, body, sess)
	}
}

func validNickname(nickname string) (string, bool) {
	nickname = strings.TrimSpace(nickname)
	return nickname, utf8.RuneCountInString(nickname) >= MinNicknameRunes
}

type profileRequest struct {
	Nickname *string `json:"nickname"`
	AvatarID *string `json:"avatarId"`
}

// applyProfile validates the given fields and applies them only if all pass.
func applyProfile(sess *session, req profileRequest) *apiError {
	nickname, avatarID := sess.nickname, sess.avatarID
	if req.Nickname != nil {
		n, ok := validNickname(*req.Nickname)
		if !ok {
			return &errInvalidNickname
		}
		nickname = n
	}
	if req.AvatarID != nil {
		if !slices.Contains(AvatarIDs, *req.AvatarID) {
			return &errInvalidAvatar
		}
		avatarID = *req.AvatarID
	}
	sess.nickname, sess.avatarID = nickname, avatarID
	return nil
}

func (s *Server) createSession(w http.ResponseWriter, r *http.Request) {
	body, ok := readBody(w, r)
	var req profileRequest
	if !ok || !decode(w, body, &req) {
		return
	}
	switch {
	case req.Nickname == nil:
		writeError(w, errInvalidNickname)
		return
	case req.AvatarID == nil:
		writeError(w, errInvalidAvatar)
		return
	}
	sess := &session{playerID: "p_" + crand.Text()}
	if err := applyProfile(sess, req); err != nil {
		writeError(w, *err)
		return
	}
	token := crand.Text()
	s.mu.Lock()
	s.sessions[token], s.players[sess.playerID] = sess, sess
	s.mu.Unlock()
	writeJSON(w, http.StatusCreated, map[string]string{"playerId": sess.playerID, "sessionToken": token})
}

func (s *Server) updateSession(w http.ResponseWriter, body []byte, sess *session) {
	var req profileRequest
	if !decode(w, body, &req) {
		return
	}
	if err := applyProfile(sess, req); err != nil {
		writeError(w, *err)
		return
	}
	if entry := s.currentRoom(sess); entry != nil {
		s.publish(entry) // nickname and avatar are part of room.state
	}
	writeJSON(w, http.StatusOK, map[string]string{"playerId": sess.playerID})
}

type settingsRequest struct {
	MaxPlayers  int      `json:"maxPlayers"`
	HintSeconds int      `json:"hintSeconds"`
	CategoryIDs []string `json:"categoryIds"`
}

func (s *Server) createRoom(w http.ResponseWriter, body []byte, sess *session) {
	var req settingsRequest
	if !decode(w, body, &req) {
		return
	}
	now := s.now()
	previous, apiErr := s.roomToLeave(sess, "", now)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	code := s.newCode()
	for s.roomsCode[code] != nil {
		code = s.newCode()
	}
	settings := room.Settings{MaxPlayers: req.MaxPlayers, HintSeconds: req.HintSeconds, CategoryIDs: req.CategoryIDs}
	rm, err := room.New(code, sess.playerID, settings, s.policy, s.rng, now)
	if err != nil {
		writeError(w, errInvalidSettings)
		return
	}
	s.leave(previous, sess, now)
	entry := &roomEntry{id: "r_" + crand.Text(), room: rm}
	s.roomsByID[entry.id], s.roomsCode[code] = entry, entry
	sess.roomID = entry.id
	s.sendSessionState(sess)
	s.publish(entry)
	writeJSON(w, http.StatusCreated, map[string]any{"room": s.roomJSON(entry)})
}

func (s *Server) joinRoom(w http.ResponseWriter, body []byte, sess *session) {
	var req struct {
		Code string `json:"code"`
	}
	if !decode(w, body, &req) {
		return
	}
	if !room.ValidCode(req.Code) {
		writeError(w, errInvalidRoomCode)
		return
	}
	entry := s.roomsCode[req.Code]
	if entry == nil {
		writeError(w, errRoomNotFound)
		return
	}
	now := s.now()
	previous, apiErr := s.roomToLeave(sess, entry.id, now)
	if apiErr != nil {
		writeError(w, *apiErr)
		return
	}
	switch err := entry.room.Join(sess.playerID, now); {
	case errors.Is(err, room.ErrRoomFull), errors.Is(err, room.ErrInGame):
		writeError(w, errRoomUnavailable)
		return
	case err != nil:
		writeError(w, errInternal)
		return
	}
	s.leave(previous, sess, now)
	sess.roomID = entry.id
	s.sendSessionState(sess)
	s.publish(entry)
	writeJSON(w, http.StatusOK, map[string]any{"room": s.roomJSON(entry)})
}

// roomToLeave returns the player's current room when moving to another one
// (nil when there is none, or it is keepID). Leaving during a game would be a
// loss, so that is refused instead. Nothing changes until leave is called,
// which happens only after the new room accepted the player.
func (s *Server) roomToLeave(sess *session, keepID string, now time.Time) (*roomEntry, *apiError) {
	entry := s.currentRoom(sess)
	if entry == nil || entry.id == keepID {
		return nil, nil
	}
	entry.room.Tick(now)
	if entry.room.View().Status == room.StatusInGame {
		return nil, &errAlreadyInGame
	}
	return entry, nil
}

// currentRoom returns the room the player is still a member of, forgetting
// one they were removed from in the meantime.
func (s *Server) currentRoom(sess *session) *roomEntry {
	entry := s.roomsByID[sess.roomID]
	if entry != nil && slices.ContainsFunc(entry.room.View().Members, func(m room.Member) bool { return m.ID == sess.playerID }) {
		return entry
	}
	sess.roomID = ""
	return nil
}

func (s *Server) leave(entry *roomEntry, sess *session, now time.Time) {
	if entry == nil {
		return
	}
	// roomToLeave checked membership and the lobby status under the same lock.
	_ = entry.room.Leave(sess.playerID, now)
	sess.roomID = ""
	s.publish(entry)
	// ponytail: empty rooms are kept; how long to keep them is an open decision.
}

type playerJSON struct {
	PlayerID  string    `json:"playerId"`
	Nickname  string    `json:"nickname"`
	AvatarID  string    `json:"avatarId"`
	Connected bool      `json:"connected"`
	JoinedAt  time.Time `json:"joinedAt"`
}

type transferJSON struct {
	FromPlayerID string              `json:"fromPlayerId"`
	ToPlayerID   string              `json:"toPlayerId"`
	Reason       room.TransferReason `json:"reason"`
}

type roomJSON struct {
	RoomID                string        `json:"roomId"`
	Code                  string        `json:"code"`
	Status                room.Status   `json:"status"`
	HostPlayerID          *string       `json:"hostPlayerId"`
	MaxPlayers            int           `json:"maxPlayers"`
	HintSeconds           int           `json:"hintSeconds"`
	CategoryIDs           []string      `json:"categoryIds"`
	SettingsLocked        bool          `json:"settingsLocked"`
	Players               []playerJSON  `json:"players"`
	HostTransfer          *transferJSON `json:"hostTransfer"`
	HostReconnectDeadline *time.Time    `json:"hostReconnectDeadline"`
}

func (s *Server) roomJSON(entry *roomEntry) roomJSON {
	v := entry.room.View()
	out := roomJSON{
		RoomID:         entry.id,
		Code:           v.Code,
		Status:         v.Status,
		MaxPlayers:     v.Settings.MaxPlayers,
		HintSeconds:    v.Settings.HintSeconds,
		CategoryIDs:    v.Settings.CategoryIDs,
		SettingsLocked: v.SettingsLocked,
		Players:        []playerJSON{},
	}
	if v.HostID != "" {
		out.HostPlayerID = &v.HostID
	}
	if t := v.HostTransfer; t != nil {
		out.HostTransfer = &transferJSON{FromPlayerID: t.From, ToPlayerID: t.To, Reason: t.Reason}
	}
	if !v.HostReconnectDeadline.IsZero() {
		deadline := v.HostReconnectDeadline.UTC()
		out.HostReconnectDeadline = &deadline
	}
	for _, m := range v.Members {
		p := playerJSON{PlayerID: m.ID, Connected: m.Connected, JoinedAt: m.JoinedAt.UTC()}
		if sess := s.players[m.ID]; sess != nil {
			p.Nickname, p.AvatarID = sess.nickname, sess.avatarID
		}
		out.Players = append(out.Players, p)
	}
	return out
}
