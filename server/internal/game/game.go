// Package game is the authoritative state machine of a single word-mode match.
//
// It knows nothing about HTTP, WebSockets or storage. Callers pass the current
// time to every call, schedule Tick at Deadline, and must serialise all calls
// for one Game (for example one goroutine or one mutex per game).
package game

import (
	"errors"
	"fmt"
	"maps"
	"math/rand/v2"
	"slices"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

const (
	MaxPlayers           = 8
	MinPlayersToStart    = 4
	MinPlayersToContinue = 3
	MaxHintRunes         = 25
	// MaxDisconnects is the disconnect count at which a player who does not
	// return within ReconnectDuration is removed.
	MaxDisconnects = 3
)

type Phase string

const (
	PhaseRoleReveal    Phase = "role_reveal"
	PhaseHints         Phase = "hints"
	PhaseVoting        Phase = "voting"
	PhaseRunoffVoting  Phase = "runoff_voting"
	PhaseImpostorGuess Phase = "impostor_guess"
	PhaseEnded         Phase = "ended"
)

type Role string

const (
	RoleCitizen  Role = "citizen"
	RoleImpostor Role = "impostor"
)

type PlayerStatus string

const (
	StatusActive  PlayerStatus = "active"
	StatusLeft    PlayerStatus = "left"
	StatusRemoved PlayerStatus = "removed" // third disconnect
)

type Team string

const (
	TeamNone     Team = "" // game stopped for lack of players
	TeamCitizens Team = "citizens"
	TeamImpostor Team = "impostor"
)

type Outcome string

const (
	OutcomeWin  Outcome = "win"
	OutcomeLoss Outcome = "loss"
)

type EndReason string

const (
	ReasonImpostorNotCaught    EndReason = "impostor_not_caught"
	ReasonSecondTie            EndReason = "second_tie"
	ReasonImpostorGuessedWord  EndReason = "impostor_guessed_word"
	ReasonImpostorGuessWrong   EndReason = "impostor_guess_wrong"
	ReasonImpostorGuessTimeout EndReason = "impostor_guess_timeout"
	ReasonImpostorGone         EndReason = "impostor_gone"
	ReasonNotEnoughPlayers     EndReason = "not_enough_players"
)

var (
	ErrInvalidSetup       = errors.New("invalid game setup")
	ErrUnknownPlayer      = errors.New("unknown player")
	ErrPlayerNotActive    = errors.New("player is no longer in the game")
	ErrWrongPhase         = errors.New("action not allowed in the current phase")
	ErrNotYourTurn        = errors.New("not your turn")
	ErrHintEmpty          = errors.New("hint is empty")
	ErrHintNotOneWord     = errors.New("hint must be a single word")
	ErrHintTooLong        = errors.New("hint is longer than 25 characters")
	ErrHintInappropriate  = errors.New("hint is inappropriate")
	ErrHintContainsSecret = errors.New("hint contains the secret word")
	ErrHintDuplicate      = errors.New("hint was already given in this game")
	ErrInvalidHint        = errors.New("no such hint")
	ErrInvalidReaction    = errors.New("unknown reaction")
	ErrSelfVote           = errors.New("cannot vote for yourself")
	ErrInvalidVoteTarget  = errors.New("player is not a vote candidate")
	ErrNotImpostor        = errors.New("only the impostor can guess")
)

type Config struct {
	HintDuration       time.Duration
	VoteDuration       time.Duration
	RunoffVoteDuration time.Duration
	GuessDuration      time.Duration
	ReconnectDuration  time.Duration
	// RoleRevealTimeout moves the game to hints even if some players have not
	// confirmed; it ends earlier once every connected player confirmed.
	RoleRevealTimeout time.Duration
}

// DefaultConfig returns the approved durations. Private rooms override HintDuration.
func DefaultConfig() Config {
	return Config{
		RoleRevealTimeout:  10 * time.Second,
		HintDuration:       15 * time.Second,
		VoteDuration:       20 * time.Second,
		RunoffVoteDuration: 15 * time.Second,
		GuessDuration:      15 * time.Second,
		ReconnectDuration:  30 * time.Second,
	}
}

// Policy holds the checks whose exact rules are still open in
// docs/open-decisions.md. All fields are required so no placeholder silently
// becomes product behaviour. The secret-word, duplicate and guess rules are
// decided and live in words.go.
type Policy struct {
	HintInappropriate func(hint string) bool
	ValidReaction     func(reactionID string) bool
}

type Hint struct {
	PlayerID  string
	Text      string
	Missing   bool           // "לא נשלח רמז"
	Reactions map[string]int // reaction ID -> count
}

type Result struct {
	Winner     Team
	Reason     EndReason
	ImpostorID string
	SecretWord string
	VoteRounds []map[string]string // counted votes per round: voter -> target
	// Abstentions counts the active players whose vote was not counted in
	// each round, whether they skipped it or were disconnected at the tally.
	Abstentions []int
	Outcomes    map[string]Outcome
}

type PlayerView struct {
	ID            string
	Status        PlayerStatus
	Connected     bool
	Disconnects   int
	RoleConfirmed bool
}

// View is what one player may see. It never carries the secret word to the
// impostor, other players' roles or votes before the game ends.
type View struct {
	Version      uint64
	Phase        Phase
	Deadline     time.Time // zero when the phase has no timer
	Category     string
	SecretWord   string
	Role         Role
	Players      []PlayerView // turn order
	CurrentTurn  string
	Reconnecting bool // current turn is waiting for its player to reconnect
	Hints        []Hint
	Candidates   []string
	// PreviousVotes counts the last round's votes per candidate. It is set
	// during a runoff, so players see who tied.
	PreviousVotes map[string]int
	MyVote        string
	Result        *Result
}

type player struct {
	status      PlayerStatus
	connected   bool
	disconnects int
	confirmed   bool
	removeAt    time.Time // set on the third disconnect until the player returns
}

type Game struct {
	cfg      Config
	policy   Policy
	category string
	secret   string
	players  map[string]*player
	order    []string
	impostor string

	phase    Phase
	deadline time.Time
	version  uint64

	turn         int
	reconnecting bool
	hints        []Hint

	candidates  []string
	votes       map[string]string
	voteRounds  []map[string]string
	abstentions []int

	result *Result
}

// New starts a game in the role-reveal phase with a random impostor and turn
// order. Category and word selection belong to the caller.
func New(cfg Config, policy Policy, playerIDs []string, category, secretWord string, rng *rand.Rand, now time.Time) (*Game, error) {
	switch {
	case len(playerIDs) < MinPlayersToStart || len(playerIDs) > MaxPlayers:
		return nil, fmt.Errorf("%w: need %d-%d players, got %d", ErrInvalidSetup, MinPlayersToStart, MaxPlayers, len(playerIDs))
	case category == "" || secretWord == "":
		return nil, fmt.Errorf("%w: category and secret word are required", ErrInvalidSetup)
	case rng == nil || policy.HintInappropriate == nil || policy.ValidReaction == nil:
		return nil, fmt.Errorf("%w: rng and every policy function are required", ErrInvalidSetup)
	case cfg.HintDuration <= 0 || cfg.VoteDuration <= 0 || cfg.RunoffVoteDuration <= 0 || cfg.GuessDuration <= 0 || cfg.ReconnectDuration <= 0 || cfg.RoleRevealTimeout <= 0:
		return nil, fmt.Errorf("%w: invalid durations", ErrInvalidSetup)
	}
	g := &Game{
		cfg:      cfg,
		policy:   policy,
		category: category,
		secret:   secretWord,
		players:  make(map[string]*player, len(playerIDs)),
		order:    slices.Clone(playerIDs),
	}
	for _, id := range playerIDs {
		if id == "" || g.players[id] != nil {
			return nil, fmt.Errorf("%w: empty or duplicate player id %q", ErrInvalidSetup, id)
		}
		g.players[id] = &player{status: StatusActive, connected: true}
	}
	rng.Shuffle(len(g.order), func(i, j int) { g.order[i], g.order[j] = g.order[j], g.order[i] })
	g.impostor = g.order[rng.IntN(len(g.order))]
	g.setPhase(PhaseRoleReveal, now, cfg.RoleRevealTimeout)
	g.version = 1
	return g, nil
}

// Version increases with every change to the game.
func (g *Game) Version() uint64 { return g.version }

// PlayerIDs returns every player dealt into the game, in turn order,
// including those who left or were removed.
func (g *Game) PlayerIDs() []string { return slices.Clone(g.order) }

// Deadline is the next moment Tick has work to do: the phase timer or a
// pending removal after a third disconnect. Zero means nothing is scheduled.
func (g *Game) Deadline() time.Time {
	next, _ := g.nextDeadline()
	return next
}

// Tick applies every deadline that has passed, in order. Commands call it
// first, so a late or stale command can never act on an expired phase.
func (g *Game) Tick(now time.Time) {
	for {
		at, removeID := g.nextDeadline()
		if at.IsZero() || now.Before(at) {
			return
		}
		if removeID != "" {
			var removeIDs []string
			for _, id := range g.order {
				p := g.players[id]
				if p.status == StatusActive && p.removeAt.Equal(at) {
					removeIDs = append(removeIDs, id)
				}
			}
			g.removeAll(removeIDs, StatusRemoved, at)
			g.version += uint64(len(removeIDs))
		} else {
			g.expire(at)
			g.version++
		}
	}
}

// nextDeadline returns the earliest deadline and, when it is a removal, the
// player to remove. Removals win ties so a removed player's turn is not skipped first.
func (g *Game) nextDeadline() (time.Time, string) {
	next, removeID := g.deadline, ""
	if g.phase == PhaseEnded {
		return next, ""
	}
	for _, id := range g.order {
		p := g.players[id]
		if p.status != StatusActive || p.removeAt.IsZero() {
			continue
		}
		if next.IsZero() || p.removeAt.Before(next) || (removeID == "" && p.removeAt.Equal(next)) {
			next, removeID = p.removeAt, id
		}
	}
	return next, removeID
}

// MarkOffline records a player who was already offline when the game was
// created, for example a private room member. Unlike Disconnect it does not
// count toward MaxDisconnects, because the disconnect did not happen during
// the game. It is part of setup, so it only works before any other call
// changed the game.
func (g *Game) MarkOffline(playerID string) error {
	p, ok := g.players[playerID]
	switch {
	case !ok:
		return ErrUnknownPlayer
	case g.version != 1:
		return ErrWrongPhase
	}
	p.connected = false
	return nil
}

func (g *Game) ConfirmRole(playerID string, now time.Time) error {
	g.Tick(now)
	p, err := g.activePlayer(playerID)
	if err != nil {
		return err
	}
	if g.phase != PhaseRoleReveal {
		return ErrWrongPhase
	}
	if !p.confirmed {
		p.confirmed = true
		g.maybeFinishRoleReveal(now)
		g.version++
	}
	return nil
}

func (g *Game) SubmitHint(playerID, text string, now time.Time) error {
	g.Tick(now)
	if _, err := g.activePlayer(playerID); err != nil {
		return err
	}
	if g.phase != PhaseHints {
		return ErrWrongPhase
	}
	if g.order[g.turn] != playerID || g.reconnecting {
		return ErrNotYourTurn
	}
	text = strings.TrimSpace(text)
	switch {
	case text == "":
		return ErrHintEmpty
	case strings.IndexFunc(text, unicode.IsSpace) >= 0:
		return ErrHintNotOneWord
	case utf8.RuneCountInString(text) > MaxHintRunes:
		return ErrHintTooLong
	}
	switch {
	case g.policy.HintInappropriate(text):
		return ErrHintInappropriate
	// The impostor does not know the word, so their hint is never checked
	// against it.
	case playerID != g.impostor && hintContainsSecret(text, g.secret):
		return ErrHintContainsSecret
	}
	for _, h := range g.hints {
		if !h.Missing && sameHint(text, h.Text) {
			return ErrHintDuplicate
		}
	}
	g.hints = append(g.hints, Hint{PlayerID: playerID, Text: text})
	g.startTurn(g.turn+1, now)
	g.version++
	return nil
}

// React adds an emoji or structured-message reaction. There is no limit, and it
// works while later turns are being written.
func (g *Game) React(playerID string, hintIndex int, reactionID string, now time.Time) error {
	g.Tick(now)
	if _, err := g.activePlayer(playerID); err != nil {
		return err
	}
	if g.phase == PhaseRoleReveal || g.phase == PhaseEnded {
		return ErrWrongPhase
	}
	if hintIndex < 0 || hintIndex >= len(g.hints) || g.hints[hintIndex].Missing {
		return ErrInvalidHint
	}
	if !g.policy.ValidReaction(reactionID) {
		return ErrInvalidReaction
	}
	h := &g.hints[hintIndex]
	if h.Reactions == nil {
		h.Reactions = map[string]int{}
	}
	h.Reactions[reactionID]++
	g.version++
	return nil
}

// Vote records or replaces the voter's choice; only the last vote counts.
func (g *Game) Vote(voterID, targetID string, now time.Time) error {
	g.Tick(now)
	if _, err := g.activePlayer(voterID); err != nil {
		return err
	}
	if g.phase != PhaseVoting && g.phase != PhaseRunoffVoting {
		return ErrWrongPhase
	}
	if voterID == targetID {
		return ErrSelfVote
	}
	if !slices.Contains(g.candidates, targetID) {
		return ErrInvalidVoteTarget
	}
	g.votes[voterID] = targetID
	g.version++
	return nil
}

func (g *Game) SubmitGuess(playerID, guess string, now time.Time) error {
	g.Tick(now)
	if _, err := g.activePlayer(playerID); err != nil {
		return err
	}
	if g.phase != PhaseImpostorGuess {
		return ErrWrongPhase
	}
	if playerID != g.impostor {
		return ErrNotImpostor
	}
	if guessMatches(guess, g.secret) {
		g.end(TeamImpostor, ReasonImpostorGuessedWord)
	} else {
		g.end(TeamCitizens, ReasonImpostorGuessWrong)
	}
	g.version++
	return nil
}

func (g *Game) Disconnect(playerID string, now time.Time) error {
	g.Tick(now)
	p, err := g.activePlayer(playerID)
	if err != nil || !p.connected {
		return err
	}
	p.connected = false
	if g.phase != PhaseEnded {
		p.disconnects++
		if p.disconnects >= MaxDisconnects {
			p.removeAt = now.Add(g.cfg.ReconnectDuration)
		}
	}
	switch {
	case g.phase == PhaseHints && g.order[g.turn] == playerID:
		g.awaitReconnect(now)
	case g.phase == PhaseRoleReveal:
		g.maybeFinishRoleReveal(now)
	}
	g.version++
	return nil
}

// Reconnect marks the player online. A player whose turn was waiting gets a
// fresh hint timer.
func (g *Game) Reconnect(playerID string, now time.Time) error {
	g.Tick(now)
	p, err := g.activePlayer(playerID)
	if err != nil || p.connected {
		return err
	}
	p.connected = true
	p.removeAt = time.Time{}
	if g.phase == PhaseHints && g.order[g.turn] == playerID {
		g.reconnecting = false
		g.setPhase(PhaseHints, now, g.cfg.HintDuration)
	}
	g.version++
	return nil
}

// Leave is a voluntary exit and a loss. Leaving after the game ended is not
// abandonment and changes nothing.
func (g *Game) Leave(playerID string, now time.Time) error {
	g.Tick(now)
	p, ok := g.players[playerID]
	if !ok {
		return ErrUnknownPlayer
	}
	if g.phase == PhaseEnded || p.status != StatusActive {
		return nil
	}
	g.remove(playerID, StatusLeft, now)
	g.version++
	return nil
}

func (g *Game) View(playerID string) (View, error) {
	if _, ok := g.players[playerID]; !ok {
		return View{}, ErrUnknownPlayer
	}
	v := View{
		Version:      g.version,
		Phase:        g.phase,
		Deadline:     g.deadline,
		Category:     g.category,
		Role:         RoleCitizen,
		Reconnecting: g.reconnecting,
		Candidates:   slices.Clone(g.candidates),
		MyVote:       g.votes[playerID],
		Result:       cloneResult(g.result),
	}
	if playerID == g.impostor {
		v.Role = RoleImpostor
	}
	if v.Role == RoleCitizen || g.phase == PhaseEnded {
		v.SecretWord = g.secret
	}
	if g.phase == PhaseHints {
		v.CurrentTurn = g.order[g.turn]
	}
	if g.phase == PhaseRunoffVoting && len(g.voteRounds) > 0 {
		// Only the players in the runoff. Counting every target would tell
		// everyone how the group voted on someone who is not even a
		// candidate, and docs/protocol.md reveals other players' votes only
		// in result.
		v.PreviousVotes = map[string]int{}
		for _, target := range g.voteRounds[len(g.voteRounds)-1] {
			if slices.Contains(g.candidates, target) {
				v.PreviousVotes[target]++
			}
		}
	}
	for _, id := range g.order {
		p := g.players[id]
		v.Players = append(v.Players, PlayerView{ID: id, Status: p.status, Connected: p.connected, Disconnects: p.disconnects, RoleConfirmed: p.confirmed})
	}
	for _, h := range g.hints {
		h.Reactions = maps.Clone(h.Reactions)
		v.Hints = append(v.Hints, h)
	}
	return v, nil
}

func (g *Game) activePlayer(id string) (*player, error) {
	p, ok := g.players[id]
	switch {
	case !ok:
		return nil, ErrUnknownPlayer
	case p.status != StatusActive:
		return nil, ErrPlayerNotActive
	}
	return p, nil
}

func (g *Game) setPhase(phase Phase, from time.Time, d time.Duration) {
	g.phase = phase
	g.deadline = time.Time{}
	if d > 0 {
		g.deadline = from.Add(d)
	}
}

func (g *Game) expire(at time.Time) {
	switch g.phase {
	case PhaseRoleReveal:
		g.startTurn(0, at)
	case PhaseHints:
		g.hints = append(g.hints, Hint{PlayerID: g.order[g.turn], Missing: true})
		g.startTurn(g.turn+1, at)
	case PhaseVoting, PhaseRunoffVoting:
		g.tally(at)
	case PhaseImpostorGuess:
		g.end(TeamCitizens, ReasonImpostorGuessTimeout)
	}
}

func (g *Game) maybeFinishRoleReveal(at time.Time) {
	for _, p := range g.players {
		if p.status == StatusActive && p.connected && !p.confirmed {
			return
		}
	}
	g.startTurn(0, at)
}

// startTurn gives the turn to the next active player at or after index i, or
// opens voting once every turn is done.
func (g *Game) startTurn(i int, at time.Time) {
	for i < len(g.order) && g.players[g.order[i]].status != StatusActive {
		i++
	}
	if i == len(g.order) {
		g.startVoting(PhaseVoting, g.activeIDs(), at, g.cfg.VoteDuration)
		return
	}
	g.turn = i
	g.reconnecting = false
	if !g.players[g.order[i]].connected {
		g.awaitReconnect(at)
		return
	}
	g.setPhase(PhaseHints, at, g.cfg.HintDuration)
}

// awaitReconnect holds the current turn for the reconnect window; if the
// player does not return, the turn is skipped.
func (g *Game) awaitReconnect(at time.Time) {
	g.reconnecting = true
	g.setPhase(PhaseHints, at, g.cfg.ReconnectDuration)
}

func (g *Game) startVoting(phase Phase, candidates []string, at time.Time, d time.Duration) {
	g.reconnecting = false
	g.candidates = candidates
	g.votes = map[string]string{}
	g.setPhase(phase, at, d)
}

func (g *Game) tally(at time.Time) {
	counted := map[string]string{}
	counts := map[string]int{}
	for voter, target := range g.votes {
		if g.players[voter].connected { // a disconnected player adds no vote
			counted[voter] = target
			counts[target]++
		}
	}
	g.voteRounds = append(g.voteRounds, counted)
	g.abstentions = append(g.abstentions, len(g.activeIDs())-len(counted))

	var top []string
	most := 0
	for _, c := range g.candidates {
		switch n := counts[c]; {
		case n > most:
			top, most = []string{c}, n
		case n == most && n > 0:
			top = append(top, c)
		}
	}
	switch {
	case len(top) == 1 && top[0] == g.impostor:
		g.setPhase(PhaseImpostorGuess, at, g.cfg.GuessDuration)
	case len(top) > 1 && g.phase == PhaseVoting:
		g.startVoting(PhaseRunoffVoting, top, at, g.cfg.RunoffVoteDuration)
	case len(top) > 1:
		g.end(TeamImpostor, ReasonSecondTie)
	default: // a citizen was selected, or nobody received a vote
		g.end(TeamImpostor, ReasonImpostorNotCaught)
	}
}

func (g *Game) remove(id string, status PlayerStatus, at time.Time) {
	g.removeAll([]string{id}, status, at)
}

func (g *Game) removeAll(ids []string, status PlayerStatus, at time.Time) {
	removedImpostor := false
	removedCurrentTurn := false
	for _, id := range ids {
		g.players[id].status = status
		removedImpostor = removedImpostor || id == g.impostor
		removedCurrentTurn = removedCurrentTurn || g.phase == PhaseHints && g.order[g.turn] == id
		for voter, target := range g.votes {
			if voter == id || target == id {
				delete(g.votes, voter)
			}
		}
		g.candidates = slices.DeleteFunc(g.candidates, func(c string) bool { return c == id })
	}

	switch {
	case removedImpostor:
		g.end(TeamCitizens, ReasonImpostorGone)
	case len(g.activeIDs()) < MinPlayersToContinue:
		g.end(TeamNone, ReasonNotEnoughPlayers)
	case g.phase == PhaseRoleReveal:
		g.maybeFinishRoleReveal(at)
	case removedCurrentTurn:
		g.startTurn(g.turn+1, at)
	}
}

func cloneResult(result *Result) *Result {
	if result == nil {
		return nil
	}
	clone := *result
	clone.Outcomes = maps.Clone(result.Outcomes)
	clone.VoteRounds = slices.Clone(result.VoteRounds)
	clone.Abstentions = slices.Clone(result.Abstentions)
	for i := range clone.VoteRounds {
		clone.VoteRounds[i] = maps.Clone(clone.VoteRounds[i])
	}
	return &clone
}

func (g *Game) end(winner Team, reason EndReason) {
	outcomes := make(map[string]Outcome, len(g.players))
	for id, p := range g.players {
		won := p.status == StatusActive &&
			(winner == TeamNone || (winner == TeamImpostor) == (id == g.impostor))
		outcomes[id] = OutcomeLoss
		if won {
			outcomes[id] = OutcomeWin
		}
	}
	g.result = &Result{
		Winner:      winner,
		Reason:      reason,
		ImpostorID:  g.impostor,
		SecretWord:  g.secret,
		VoteRounds:  g.voteRounds,
		Abstentions: g.abstentions,
		Outcomes:    outcomes,
	}
	g.reconnecting = false
	g.setPhase(PhaseEnded, time.Time{}, 0)
}

func (g *Game) activeIDs() []string {
	var ids []string
	for _, id := range g.order {
		if g.players[id].status == StatusActive {
			ids = append(ids, id)
		}
	}
	return ids
}
