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
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/dorohayon/Imposter-IL/server/internal/content"
	"github.com/dorohayon/Imposter-IL/server/internal/game"
	"github.com/dorohayon/Imposter-IL/server/internal/matchmaking"
	"github.com/dorohayon/Imposter-IL/server/internal/monetization"
	"github.com/dorohayon/Imposter-IL/server/internal/room"
)

// MinNicknameRunes and MaxNicknameRunes are the approved bounds after
// trimming (docs/decisions.md). Allowed characters are still an open decision.
const (
	MinNicknameRunes = 2
	MaxNicknameRunes = 18
)

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
	token    string // key in Server.sessions, so the reaper can delete it
	nickname string
	avatarID string
	roomID   string // current room: a private room or a forming online match

	// lastSeen is refreshed by every request, command and connection change;
	// the reaper drops a session idle for SessionTTL.
	lastSeen time.Time
	// ip is the caller's address as of the last request, for per-IP limits in
	// handlers that only receive the session.
	ip string
	// connected is set the first time a WebSocket attaches. A session that
	// never did is reaped within minutes rather than kept for a day: that is
	// what bounds memory against someone looping POST /v1/sessions.
	connected bool
	bot       bool // staging-only server actor; never has a token or WebSocket
	// botActAt is when a staging bot has finished "thinking" and may act.
	// Zero when it has nothing pending.
	botActAt time.Time
	// botReactAt and botReacted drive reactions, which a bot sends while
	// another player has the turn, so they cannot share botActAt.
	botReactAt time.Time
	botReacted int // hints the bot has already had its chance to react to

	// What the store proofs this device sent last prove it owns
	// (POST /v1/entitlements). Checked only under ServerEnforcement.
	entitlements monetization.Entitlements

	// The categories and start time of the player's latest online search.
	searchCategories []string
	searchStarted    time.Time

	conn    *conn // current WebSocket, if connected
	replies replyCache

	// The game this player is showing, from its start until they leave it or
	// return to the lobby. It outlives room membership and later games in the
	// room, so a player removed on a third disconnect still sees that game
	// (screen 27) and can leave it.
	gameID   string
	game     *game.Game
	gameRoom *roomEntry

	// The last outcome authoritatively settled by game.leave. Repeating it in
	// session.state lets a client recover when the socket drops after the
	// command ran but before its reply arrived. Clients deduplicate by game id.
	lastGameID      string
	lastGameOutcome game.Outcome
}

type playerProfile struct{ nickname, avatarID string }

type roomEntry struct {
	id     string
	code   string // kept here so a room can be dropped without asking it
	room   *room.Room
	timer  *time.Timer // fires at room.Deadline()
	gameID string      // id of room.Game(), if one was started

	// emptySince is when the last member left, for the reaper.
	emptySince time.Time

	// reported records, for the room's current game, who reported whom:
	// reported player -> reporters. Reset when a game begins.
	reported map[string]map[string]bool

	// categoriesBy is the player whose purchases the private room's categories
	// were checked against: its creator, or whoever last changed them.
	categoriesBy string

	// profiles are the nickname and avatar of everyone dealt into the room's
	// game, captured when it started. A finished game still has to name its
	// players on the result screen, and by then a session may be gone — a
	// staging bot's is deleted the moment the match settles.
	profiles map[string]playerProfile

	// Online matches (public rooms, see matchmaking.go).
	public       bool
	timers       matchmaking.Timers
	lobbyVersion uint64     // rises when the searchers or timers change
	settled      *game.Game // the finished game whose players were released
	// stagingBotJoinAt schedules the next bot joins while humans search alone.
	stagingBotJoinAt []time.Time

	// stateVersion numbers the snapshots sent for this room: room.state and
	// game.state each take the next value, so it rises on any published change,
	// including profile edits and a new game, and never repeats across types.
	stateVersion uint64
	// published is what the last snapshot reflected; sync publishes when the
	// room or its game has moved on since, for example through a deadline
	// applied by a command that then failed.
	published snapshotMark
}

type snapshotMark struct {
	roomVersion  uint64
	lobbyVersion uint64
	game         *game.Game
	gameVersion  uint64
}

// Server holds sessions, rooms and connections.
// ponytail: one lock for everything, including room timers; move each room
// into its own actor goroutine if lock contention shows up.
type Server struct {
	now          func() time.Time
	policy       game.Policy
	pickWord     PickWord
	newCode      func() string
	pingInterval time.Duration

	mu          sync.Mutex
	rng         *rand.Rand
	sessions    map[string]*session // token -> session
	players     map[string]*session // player id -> session
	roomsByID   map[string]*roomEntry
	roomsCode   map[string]*roomEntry
	publicRooms []*roomEntry // online matches, oldest first

	draining   bool // no new rooms, searches or games; see ops.go
	trustProxy bool // read the client address from X-Forwarded-For
	minBuild   int  // oldest app build allowed in; 0 accepts every client

	sessionLimit *limiter // guest creation, per IP
	joinLimit    *limiter // room-code attempts, per IP
	commandLimit *limiter // WebSocket commands, per session
	// entitlementLimit and entitlementIPLimit bound purchase verification,
	// per session and per IP (monetization.go).
	entitlementLimit   *limiter
	entitlementIPLimit *limiter

	money     monetization.Config
	verifiers map[string]monetization.Verifier

	metrics metrics

	// Optional staging-only actors. Zero is the production default. Bots are
	// created only while at least one real player is searching or playing.
	stagingBots int
	botSequence uint64
	botHint     uint64
}

// NewServer uses policy and pickWord for games started in rooms. Without
// them room.start fails with content_unavailable.
func NewServer(now func() time.Time, policy game.Policy, pickWord PickWord) *Server {
	var seed [32]byte
	_, _ = crand.Read(seed[:])
	s := &Server{
		now:          now,
		policy:       policy,
		pickWord:     pickWord,
		pingInterval: 10 * time.Second,
		rng:          rand.New(rand.NewChaCha8(seed)),
		sessions:     map[string]*session{},
		players:      map[string]*session{},
		roomsByID:    map[string]*roomEntry{},
		roomsCode:    map[string]*roomEntry{},
		sessionLimit: newLimiter(sessionsPerMinute, sessionsBurst),
		joinLimit:    newLimiter(joinsPerMinute, joinsBurst),
		commandLimit: newLimiter(commandsPerMinute, commandsBurst),

		entitlementLimit:   newLimiter(entitlementsPerMin, entitlementsBurst),
		entitlementIPLimit: newLimiter(entitlementsPerMinPerIP, entitlementsBurstPerIP),
		money:              monetization.Default(),
	}
	s.newCode = func() string { return room.NewCode(s.rng) }
	return s
}

// EnableStagingBots lets one real online player reach the four-player minimum
// without an external always-on worker. Up to five may join a search so the
// forming table can be exercised; a match still needs a real player. Leave
// disabled in production.
func (s *Server) EnableStagingBots(count int) {
	if count < 0 {
		count = 0
	}
	const maxStagingBots = 5
	if count > maxStagingBots {
		count = maxStagingBots
	}
	s.mu.Lock()
	s.stagingBots = count
	s.mu.Unlock()
}

// RequireClientBuild refuses clients older than build. The app sends its build
// number in X-Client-Build; a store release stays installed for years, so
// without this gate there is no way to retire a protocol the old build speaks.
// Zero, the default, accepts every client including ones that send no header.
func (s *Server) RequireClientBuild(build int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.minBuild = build
}

// clientTooOld reports whether the request comes from a build we no longer
// serve. A missing or unparsable header is treated as build 0, so only an
// explicit minimum can lock anyone out.
func (s *Server) clientTooOld(r *http.Request) bool {
	s.mu.Lock()
	min := s.minBuild
	s.mu.Unlock()
	if min <= 0 {
		return false
	}
	build, err := strconv.Atoi(r.Header.Get("X-Client-Build"))
	return err != nil || build < min
}

func (s *Server) gate(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.clientTooOld(r) {
			writeError(w, errClientTooOld)
			return
		}
		next(w, r)
	}
}

func (s *Server) Routes(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/sessions", s.gate(s.createSession))
	mux.HandleFunc("GET /v1/config", s.gate(s.getConfig))
	mux.HandleFunc("POST /v1/entitlements", s.gate(s.syncEntitlements))
	mux.HandleFunc("GET /v1/categories", s.gate(s.withSession(listCategories)))
	mux.HandleFunc("GET /v1/reactions", s.gate(s.withSession(listReactions)))
	mux.HandleFunc("PATCH /v1/sessions/me", s.gate(s.withSession(s.updateSession)))
	mux.HandleFunc("POST /v1/rooms", s.gate(s.withSession(s.createRoom)))
	mux.HandleFunc("POST /v1/rooms/join", s.gate(s.withSession(s.joinRoom)))
	mux.HandleFunc("GET /v1/ws", s.gate(s.serveWS))
}

type apiError struct {
	status  int
	code    string
	message string
}

var (
	errInvalidMessage  = apiError{http.StatusBadRequest, "invalid_message", "invalid request body"}
	errSessionNotFound = apiError{http.StatusUnauthorized, "session_not_found", "session not found"}
	errInvalidNickname = apiError{http.StatusUnprocessableEntity, "invalid_nickname", "nickname must have 2 to 18 characters"}
	errInvalidAvatar   = apiError{http.StatusUnprocessableEntity, "invalid_avatar", "unknown avatar"}
	errInvalidSettings = apiError{http.StatusUnprocessableEntity, "invalid_room_settings", "invalid room settings"}
	errInvalidRoomCode = apiError{http.StatusUnprocessableEntity, "invalid_room_code", "room code must be six digits"}
	errRoomNotFound    = apiError{http.StatusNotFound, "room_not_found", "room not found"}
	errRoomUnavailable = apiError{http.StatusConflict, "room_unavailable", "room is full or in a game"}
	errAlreadyInGame   = apiError{http.StatusConflict, "already_in_activity", "leave the current game first"}
	errInternal        = apiError{http.StatusInternalServerError, "internal_error", "internal error"}
	errDraining        = apiError{http.StatusServiceUnavailable, "server_draining", "server is restarting, try again in a moment"}
	errClientTooOld    = apiError{http.StatusUpgradeRequired, "client_too_old", "update the app to keep playing"}
	errNicknameBlocked = apiError{http.StatusUnprocessableEntity, "nickname_blocked", "nickname is not allowed"}
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
		// A panic here would leave the player's room half-changed; abort that
		// room rather than serve from state nobody has checked.
		defer s.recoverRoom(s.roomsByID[sess.roomID], "rest "+r.Pattern)
		sess.lastSeen, sess.ip = s.now(), s.clientIP(r)
		next(w, body, sess)
		s.syncSession(sess)
	}
}

func validNickname(nickname string) (string, bool) {
	nickname = strings.TrimSpace(nickname)
	runes := utf8.RuneCountInString(nickname)
	return nickname, runes >= MinNicknameRunes && runes <= MaxNicknameRunes
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
		// Nicknames are shown to strangers, so they go through the same
		// blocklist as hints (screen 2).
		if content.Blocked(n) {
			return &errNicknameBlocked
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
	s.mu.Lock()
	now := s.now()
	if !s.sessionLimit.allow(s.clientIP(r), now) {
		s.metrics.rateLimited++
		s.mu.Unlock()
		writeError(w, errRateLimited)
		return
	}
	s.mu.Unlock()

	sess := &session{playerID: "p_" + crand.Text(), lastSeen: now, ip: s.clientIP(r)}
	if err := applyProfile(sess, req); err != nil {
		writeError(w, *err)
		return
	}
	token := crand.Text()
	sess.token = token
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

func listCategories(w http.ResponseWriter, _ []byte, _ *session) {
	categories := []map[string]string{}
	for _, c := range content.Categories {
		categories = append(categories, map[string]string{"id": c.ID, "name": c.Name})
	}
	writeJSON(w, http.StatusOK, map[string]any{"categories": categories})
}

func listReactions(w http.ResponseWriter, _ []byte, _ *session) {
	reactions := []map[string]string{}
	for _, r := range content.Reactions {
		reactions = append(reactions, map[string]string{"id": r.ID, "text": r.Text})
	}
	writeJSON(w, http.StatusOK, map[string]any{"reactions": reactions})
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
	if s.draining {
		writeError(w, errDraining)
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
	if err != nil || !content.ValidIDs(req.CategoryIDs) {
		writeError(w, errInvalidSettings)
		return
	}
	if !s.categoriesAllowed(sess, req.CategoryIDs, now) {
		writeError(w, errCategoryLocked)
		return
	}
	s.leave(previous, sess, now)
	entry := &roomEntry{id: "r_" + crand.Text(), code: code, room: rm, categoriesBy: sess.playerID}
	s.roomsByID[entry.id], s.roomsCode[code] = entry, entry
	sess.roomID = entry.id
	sess.leaveGame()
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
	if s.draining {
		writeError(w, errDraining)
		return
	}
	// Rate limited before the lookup: this is the room-code enumeration path.
	if !s.joinLimit.allow(sess.ip, s.now()) {
		s.metrics.rateLimited++
		writeError(w, errRateLimited)
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
		s.sync(entry) // Join applied the room's expired deadlines first
		writeError(w, errRoomUnavailable)
		return
	case err != nil:
		writeError(w, errInternal)
		return
	}
	s.leave(previous, sess, now)
	sess.roomID = entry.id
	sess.leaveGame()
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
	if entry.public {
		s.leaveSearch(sess, entry, now)
	} else {
		_ = entry.room.Leave(sess.playerID, now)
		sess.roomID = ""
	}
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
