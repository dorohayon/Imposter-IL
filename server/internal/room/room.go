// Package room is the authoritative state machine of one private room: its
// code, members, host, settings lock, host transfer, and the games played in
// it. The room stays open between games.
//
// Like package game it knows nothing about HTTP, WebSockets or storage.
// Callers pass the current time to every call, schedule Tick at Deadline, and
// must serialise all calls for one Room. Finding a room by code belongs to the
// caller.
package room

import (
	"cmp"
	"errors"
	"fmt"
	"math/rand/v2"
	"slices"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

const (
	CodeDigits            = 6
	MinPlayers            = game.MinPlayersToStart
	MaxPlayers            = game.MaxPlayers
	HostReconnectDuration = 30 * time.Second
)

// DefaultHintSeconds is the approved turn length (docs/decisions.md).
const DefaultHintSeconds = 60

// HintSecondsOptions are the hint durations a host may choose, around the
// approved default.
var HintSecondsOptions = []int{30, DefaultHintSeconds, 90}

type Status string

const (
	StatusLobby  Status = "lobby"
	StatusInGame Status = "in_game"
)

type TransferReason string

const (
	ReasonHostTimeout TransferReason = "host_timeout"
	ReasonHostLeft    TransferReason = "host_left"
	ReasonHostRemoved TransferReason = "host_removed" // third disconnect in a game
)

var (
	ErrInvalidCode      = errors.New("room code must be six digits")
	ErrInvalidSettings  = errors.New("invalid room settings")
	ErrInvalidPlayerID  = errors.New("player id is required")
	ErrUnknownPlayer    = errors.New("player is not in the room")
	ErrNotHost          = errors.New("only the host can do this")
	ErrSettingsLocked   = errors.New("room settings are locked")
	ErrCannotKickSelf   = errors.New("the host cannot remove themself")
	ErrNotEnoughPlayers = errors.New("not enough players to start")
	ErrRoomFull         = errors.New("room is full")
	ErrInGame           = errors.New("a game is in progress")
	ErrNoGame           = errors.New("no game has been played in this room")
)

type Settings struct {
	MaxPlayers  int
	HintSeconds int
	CategoryIDs []string
}

func (s Settings) validate() error {
	if s.MaxPlayers < MinPlayers || s.MaxPlayers > MaxPlayers ||
		!slices.Contains(HintSecondsOptions, s.HintSeconds) ||
		len(s.CategoryIDs) == 0 || slices.Contains(s.CategoryIDs, "") {
		return ErrInvalidSettings
	}
	return nil
}

type Member struct {
	ID        string
	Connected bool
	JoinedAt  time.Time
}

type HostTransfer struct {
	From, To string
	Reason   TransferReason
}

// View is the room.state snapshot; members are in join order.
type View struct {
	Version               uint64
	Code                  string
	Status                Status
	HostID                string // empty while waiting for a member to take over
	Settings              Settings
	SettingsLocked        bool
	Members               []Member
	HostTransfer          *HostTransfer // latest transfer, for screen 22
	HostReconnectDeadline time.Time     // zero unless waiting for a disconnected host
}

type Room struct {
	code     string
	settings Settings
	locked   bool
	members  []Member // join order, so the longest-present member comes first
	host     string
	status   Status
	version  uint64

	hostDeadline time.Time
	// hostPendingFrom is the host who missed the reconnect deadline while
	// nobody else was connected. The room then has no host until another
	// member connects or joins; the original host cannot take it back.
	hostPendingFrom string
	transfer        *HostTransfer

	policy       game.Policy
	rng          *rand.Rand
	game         *game.Game // current game, or the last one for its result
	participants []string
}

// ValidCode reports whether code has exactly six digits.
func ValidCode(code string) bool {
	if len(code) != CodeDigits {
		return false
	}
	for _, c := range code {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// NewCode returns a random six-digit code. Uniqueness among open rooms is the
// caller's job.
// ponytail: plain math/rand; code guessing and rate limits are an open task
// (TASKS.md), switch to crypto/rand there if codes must be unpredictable.
func NewCode(rng *rand.Rand) string {
	return fmt.Sprintf("%06d", rng.IntN(1_000_000))
}

// New opens a room in the lobby with the host as its only, connected member.
// The policy and rng are used for every game started in the room.
func New(code, hostID string, settings Settings, policy game.Policy, rng *rand.Rand, now time.Time) (*Room, error) {
	switch {
	case !ValidCode(code):
		return nil, ErrInvalidCode
	case hostID == "" || rng == nil:
		return nil, fmt.Errorf("%w: host id and rng are required", ErrInvalidSettings)
	}
	if err := settings.validate(); err != nil {
		return nil, err
	}
	settings.CategoryIDs = slices.Clone(settings.CategoryIDs)
	return &Room{
		code:     code,
		settings: settings,
		members:  []Member{{ID: hostID, Connected: true, JoinedAt: now}},
		host:     hostID,
		status:   StatusLobby,
		policy:   policy,
		rng:      rng,
	}, nil
}

// Join adds a player. Joining again while already a member changes nothing.
// The first other player to join locks the settings for good. A player who
// joins a room that everyone left becomes its host.
func (r *Room) Join(playerID string, now time.Time) error {
	if playerID == "" {
		return ErrInvalidPlayerID
	}
	r.Tick(now)
	if r.member(playerID) != nil {
		return nil
	}
	switch {
	case r.status == StatusInGame:
		return ErrInGame
	case len(r.members) >= r.settings.MaxPlayers:
		return ErrRoomFull
	}
	r.members = append(r.members, Member{ID: playerID, Connected: true, JoinedAt: now})
	r.locked = true
	switch {
	case r.hostPendingFrom != "":
		r.transferHost(ReasonHostTimeout, now)
	case r.host == "":
		// Everyone had left, so there is nobody to hand over from: the room
		// stays joinable by code and the first player back runs it.
		r.host, r.transfer = playerID, nil
	}
	r.version++
	return nil
}

func (r *Room) UpdateSettings(byID string, settings Settings, now time.Time) error {
	if err := r.hostInLobby(byID, now); err != nil {
		return err
	}
	if r.locked {
		return ErrSettingsLocked
	}
	if err := settings.validate(); err != nil {
		return err
	}
	settings.CategoryIDs = slices.Clone(settings.CategoryIDs)
	r.settings = settings
	r.version++
	return nil
}

// Kick removes another player from the lobby.
func (r *Room) Kick(byID, playerID string, now time.Time) error {
	if err := r.hostInLobby(byID, now); err != nil {
		return err
	}
	if playerID == byID {
		return ErrCannotKickSelf
	}
	if !r.removeMember(playerID) {
		return ErrUnknownPlayer
	}
	r.version++
	return nil
}

// Start begins a game with every member. Members who are offline join the
// game offline, without a counted disconnect. Category and word selection
// belong to the caller.
func (r *Room) Start(byID, category, secretWord string, now time.Time) error {
	if err := r.hostInLobby(byID, now); err != nil {
		return err
	}
	return r.start(category, secretWord, now)
}

// StartByServer starts a game without a host command, for online matches
// whose start the server decides.
func (r *Room) StartByServer(category, secretWord string, now time.Time) error {
	r.Tick(now)
	if r.status == StatusInGame {
		return ErrInGame
	}
	return r.start(category, secretWord, now)
}

func (r *Room) start(category, secretWord string, now time.Time) error {
	if len(r.members) < MinPlayers {
		return ErrNotEnoughPlayers
	}
	ids := make([]string, len(r.members))
	for i, m := range r.members {
		ids[i] = m.ID
	}
	cfg := game.DefaultConfig()
	cfg.HintDuration = time.Duration(r.settings.HintSeconds) * time.Second
	g, err := game.New(cfg, r.policy, ids, category, secretWord, r.rng, now)
	if err != nil {
		return err
	}
	for _, m := range r.members {
		if !m.Connected {
			if err := g.MarkOffline(m.ID); err != nil {
				return err
			}
		}
	}
	r.game, r.participants, r.status = g, ids, StatusInGame
	r.version++
	return nil
}

// WithGame runs a game command (hint, vote, reaction, guess, role
// confirmation) on the current or last game, then applies its effects on the
// room: players who left or were removed leave the room, and a finished game
// returns the room to the lobby. Use Leave, Disconnect and Reconnect on the
// room instead of on the game.
func (r *Room) WithGame(now time.Time, command func(*game.Game) error) error {
	if r.game == nil {
		return ErrNoGame
	}
	r.Tick(now)
	err := command(r.game)
	r.syncGame(now)
	return err
}

// Game returns the current or last game, or nil. Use it for read-only views.
func (r *Room) Game() *game.Game { return r.game }

// Leave is a voluntary exit from the room, and a loss when it happens during
// a game. A leaving host hands over immediately.
func (r *Room) Leave(playerID string, now time.Time) error {
	r.Tick(now)
	if r.member(playerID) == nil {
		return ErrUnknownPlayer
	}
	if r.status == StatusInGame && slices.Contains(r.participants, playerID) {
		if err := r.game.Leave(playerID, now); err != nil {
			return err
		}
	}
	r.removeMember(playerID)
	if playerID == r.host {
		r.transferHost(ReasonHostLeft, now)
	}
	r.syncGame(now)
	r.version++
	return nil
}

// Disconnect marks a member offline. A disconnected host has
// HostReconnectDuration to return before the room is handed over.
func (r *Room) Disconnect(playerID string, now time.Time) error {
	r.Tick(now)
	m := r.member(playerID)
	if m == nil {
		return ErrUnknownPlayer
	}
	if !m.Connected {
		return nil
	}
	m.Connected = false
	if r.status == StatusInGame && slices.Contains(r.participants, playerID) {
		if err := r.game.Disconnect(playerID, now); err != nil {
			return err
		}
	}
	if playerID == r.host {
		r.hostDeadline = now.Add(HostReconnectDuration)
	}
	r.syncGame(now)
	r.version++
	return nil
}

// Reconnect marks a member online. A former host who returns late stays a
// regular member.
func (r *Room) Reconnect(playerID string, now time.Time) error {
	r.Tick(now)
	m := r.member(playerID)
	if m == nil {
		return ErrUnknownPlayer
	}
	if m.Connected {
		return nil
	}
	m.Connected = true
	if r.status == StatusInGame && slices.Contains(r.participants, playerID) {
		if err := r.game.Reconnect(playerID, now); err != nil {
			return err
		}
	}
	switch {
	// Checked first: a host who missed the deadline is no longer host.
	case r.hostPendingFrom != "":
		if playerID != r.hostPendingFrom {
			r.transferHost(ReasonHostTimeout, now)
		}
	case playerID == r.host:
		r.hostDeadline = time.Time{}
	}
	r.syncGame(now)
	r.version++
	return nil
}

// Deadline is the next moment Tick has work to do. Zero means nothing is scheduled.
func (r *Room) Deadline() time.Time {
	next := r.hostDeadline
	if r.status == StatusInGame {
		if d := r.game.Deadline(); !d.IsZero() && (next.IsZero() || d.Before(next)) {
			next = d
		}
	}
	return next
}

// Tick applies game deadlines and the host reconnect deadline that have passed.
func (r *Room) Tick(now time.Time) {
	if r.status == StatusInGame {
		// Game removals first: a host removed on a third disconnect is
		// host_removed even when the host timer ends at the same moment.
		r.game.Tick(now)
		r.syncGame(now)
	}
	if !r.hostDeadline.IsZero() && !now.Before(r.hostDeadline) {
		r.transferHost(ReasonHostTimeout, r.hostDeadline)
		r.version++
	}
}

// Empty reports whether everyone has left. How long an empty room is kept is
// an open decision, so closing it is the caller's job.
func (r *Room) Empty() bool { return len(r.members) == 0 }

func (r *Room) View() View {
	return View{
		Version:               r.version,
		Code:                  r.code,
		Status:                r.status,
		HostID:                r.host,
		Settings:              Settings{MaxPlayers: r.settings.MaxPlayers, HintSeconds: r.settings.HintSeconds, CategoryIDs: slices.Clone(r.settings.CategoryIDs)},
		SettingsLocked:        r.locked,
		Members:               slices.Clone(r.members),
		HostTransfer:          cloneTransfer(r.transfer),
		HostReconnectDeadline: r.hostDeadline,
	}
}

func cloneTransfer(t *HostTransfer) *HostTransfer {
	if t == nil {
		return nil
	}
	clone := *t
	return &clone
}

func (r *Room) hostInLobby(byID string, now time.Time) error {
	r.Tick(now)
	switch {
	case r.member(byID) == nil:
		return ErrUnknownPlayer
	case byID != r.host:
		return ErrNotHost
	case r.status == StatusInGame:
		return ErrInGame
	}
	return nil
}

func (r *Room) member(id string) *Member {
	for i := range r.members {
		if r.members[i].ID == id {
			return &r.members[i]
		}
	}
	return nil
}

func (r *Room) removeMember(id string) bool {
	n := len(r.members)
	r.members = slices.DeleteFunc(r.members, func(m Member) bool { return m.ID == id })
	return len(r.members) < n
}

// transferHost hands the room to the connected member who has been in it the
// longest, never back to the host being replaced. On a timeout with nobody
// else connected the room has no host until another member connects or joins.
// A host who left or was removed is always replaced while anyone remains; if
// the new host is offline, their own reconnect timer starts.
func (r *Room) transferHost(reason TransferReason, at time.Time) {
	from := cmp.Or(r.host, r.hostPendingFrom)
	r.hostDeadline, r.hostPendingFrom = time.Time{}, ""
	var to *Member
	for i := range r.members {
		if m := &r.members[i]; m.ID != from && m.Connected {
			to = m
			break
		}
	}
	if to == nil && reason == ReasonHostTimeout {
		r.host, r.hostPendingFrom = "", from
		return
	}
	if to == nil {
		if len(r.members) == 0 {
			r.host = ""
			return
		}
		to = &r.members[0]
	}
	r.host = to.ID
	r.transfer = &HostTransfer{From: from, To: to.ID, Reason: reason}
	if !to.Connected {
		r.hostDeadline = at.Add(HostReconnectDuration)
	}
}

// syncGame removes members who left or were removed from the game and
// returns the room to the lobby when the game has ended.
func (r *Room) syncGame(now time.Time) {
	if r.status != StatusInGame {
		return
	}
	v, err := r.game.View(r.participants[0]) // any participant sees every status
	if err != nil {
		return
	}
	for _, p := range v.Players {
		if p.Status == game.StatusActive || !r.removeMember(p.ID) {
			continue
		}
		if p.ID == r.host {
			reason := ReasonHostLeft
			if p.Status == game.StatusRemoved {
				reason = ReasonHostRemoved
			}
			r.transferHost(reason, now)
		}
		r.version++
	}
	if v.Phase == game.PhaseEnded {
		r.status = StatusLobby
		r.version++
	}
}
