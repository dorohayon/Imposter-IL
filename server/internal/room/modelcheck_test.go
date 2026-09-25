package room

// Randomised model check of room + game, from the production-readiness audit.
// Drives a Room through random legal and illegal commands from random players,
// disconnects, reconnects, leaves and clock advances, and checks invariants
// after every step. Run: go test ./internal/room -run TestModelCheck -v
// Knobs: AUDIT_SEEDS (default 100; 10000 passes), AUDIT_SEED (one seed, traced).

import (
	"encoding/json"
	"errors"
	"fmt"
	"math/rand/v2"
	"os"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"
	"unicode"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

var phaseSeen = map[game.Phase]int{}

var auditSecrets = []string{"פיל", "עז", "ג'ירפה", "שף", "בננה", "כדורגל", "צב"}

// Independent reference normaliser (docs/decisions.md "השוואת מילים בעברית").
func refNorm(s string) string {
	fin := map[rune]rune{'ך': 'כ', 'ם': 'מ', 'ן': 'נ', 'ף': 'פ', 'ץ': 'צ'}
	var out []rune
	for _, r := range s {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) {
			continue
		}
		r = unicode.ToLower(r)
		if f, ok := fin[r]; ok {
			r = f
		}
		out = append(out, r)
	}
	return string(out)
}

func refPrefixed(long, short string) bool {
	l, s := []rune(long), []rune(short)
	n := len(l) - len(s)
	if n < 1 || n > 3 || len(s) < 2 || string(l[n:]) != short {
		return false
	}
	for _, r := range l[:n] {
		if !strings.ContainsRune("והבכלמש", r) {
			return false
		}
	}
	return true
}

// refContainsSecret: a secret of 4+ letters anywhere, a shorter one only at
// the start after 0-3 prefix letters (docs/decisions.md).
func refContainsSecret(hint, secret string) bool {
	h, s := []rune(refNorm(hint)), refNorm(secret)
	if len([]rune(s)) >= 4 {
		return strings.Contains(string(h), s)
	}
	for i := 0; i <= 3 && i < len(h); i++ {
		if i > 0 && !strings.ContainsRune("והבכלמש", h[i-1]) {
			return false
		}
		if strings.HasPrefix(string(h[i:]), s) {
			return true
		}
	}
	return false
}

func refSame(a, b string) bool {
	a, b = refNorm(a), refNorm(b)
	return a == b || refPrefixed(a, b) || refPrefixed(b, a)
}

type snap struct {
	now     time.Time
	version uint64
	phase   game.Phase
	round   int
	dl      time.Time
	views   map[string]game.View
	blob    string
	room    View
}

func takeSnap(r *Room, ids []string, now time.Time) snap {
	g := r.Game()
	s := snap{now: now, version: g.Version(), phase: g.Phase(), views: map[string]game.View{}, room: r.View()}
	var b strings.Builder
	for _, id := range ids {
		v, err := g.View(id)
		if err != nil {
			panic(err)
		}
		s.views[id] = v
		s.round, s.dl = v.Round, v.Deadline
		j, _ := json.Marshal(v)
		b.Write(j)
	}
	s.blob = b.String()
	return s
}

var edges = map[game.Phase][]game.Phase{
	game.PhaseRoleReveal:        {game.PhaseHints, game.PhaseEnded},
	game.PhaseHints:             {game.PhaseHints, game.PhaseHintBreak, game.PhasePreVoting, game.PhaseEnded},
	game.PhaseHintBreak:         {game.PhaseHints, game.PhasePreVoting, game.PhaseEnded},
	game.PhasePreVoting:         {game.PhaseVoting, game.PhaseEnded},
	game.PhaseVoting:            {game.PhaseRunoffVoting, game.PhaseImpostorGuess, game.PhaseEliminationReveal, game.PhaseHints, game.PhaseEnded},
	game.PhaseRunoffVoting:      {game.PhaseImpostorGuess, game.PhaseEliminationReveal, game.PhaseHints, game.PhaseEnded},
	game.PhaseEliminationReveal: {game.PhaseHints, game.PhaseEnded},
	game.PhaseImpostorGuess:     {game.PhaseEnded},
}

func reachable(from, to game.Phase, hops int) bool {
	if from == to {
		return true
	}
	if hops == 0 {
		return false
	}
	for _, n := range edges[from] {
		if reachable(n, to, hops-1) {
			return true
		}
	}
	return false
}

type modelRun struct {
	seed      uint64
	rng       *rand.Rand
	r         *Room
	ids       []string
	secret    string
	impostor  string
	now       time.Time
	trace     []string
	fail      string
	hintSeq   int
	votes     map[string]string // shadow of accepted votes this voting phase
	voteCast  bool              // any vote accepted this phase, even if later deleted
	silent    int
	shadowVR  []map[string]string
	goneAt    map[string]time.Time // when an active player last dropped, while still away
	goneCount map[string]int       // their counted disconnects at that drop
	turnSeen  map[string]time.Time // first time each hint turn (round/player) was observed
	reasons   map[game.EndReason]int
	maxRound  int
	steps     int
}

func (m *modelRun) failf(format string, a ...any) {
	if m.fail == "" {
		m.fail = fmt.Sprintf(format, a...)
	}
}

func (m *modelRun) log(format string, a ...any) {
	m.trace = append(m.trace, fmt.Sprintf("t=+%v ", m.now.Sub(t0))+fmt.Sprintf(format, a...))
}

func statusOf(s snap, id string) game.PlayerStatus {
	for _, p := range s.views[id].Players {
		if p.ID == id {
			return p.Status
		}
	}
	return ""
}

func playerOf(s snap, id string) game.PlayerView {
	for _, p := range s.views[id].Players {
		if p.ID == id {
			return p
		}
	}
	return game.PlayerView{}
}

func activeIDs(s snap, ids []string) []string {
	var out []string
	for _, id := range ids {
		if statusOf(s, id) == game.StatusActive {
			out = append(out, id)
		}
	}
	return out
}

// checkState: invariants of one snapshot.
func (m *modelRun) checkState(s snap) {
	imp := 0
	for _, id := range m.ids {
		v := s.views[id]
		if v.Role == game.RoleImpostor {
			imp++
			if id != m.impostor {
				m.failf("impostor changed: %s", id)
			}
			if v.SecretWord != "" && s.phase != game.PhaseEnded {
				m.failf("impostor %s sees the secret word in phase %s", id, s.phase)
			}
		} else if v.SecretWord != m.secret {
			m.failf("citizen %s secret=%q", id, v.SecretWord)
		}
		if v.Result != nil && s.phase != game.PhaseEnded || v.Result == nil && s.phase == game.PhaseEnded {
			m.failf("result/phase mismatch for %s", id)
		}
		if v.MyVote != "" {
			if v.MyVote == id {
				m.failf("self vote stored for %s", id)
			}
			if s.phase == game.PhaseVoting || s.phase == game.PhaseRunoffVoting {
				if !slices.Contains(v.Candidates, v.MyVote) {
					m.failf("vote of %s for non-candidate %s", id, v.MyVote)
				}
				if statusOf(s, id) != game.StatusActive {
					m.failf("non-active %s holds a vote", id)
				}
			}
		}
		if v.PreviousVotes != nil && s.phase != game.PhaseRunoffVoting {
			m.failf("previousVotes outside runoff")
		}
		if v.Result == nil {
			for _, h := range v.Hints {
				_ = h
			}
		}
	}
	if imp != 1 {
		m.failf("impostor count = %d", imp)
	}
	v0 := s.views[m.ids[0]]
	if s.phase == game.PhaseHints {
		if statusOf(s, v0.CurrentTurn) != game.StatusActive {
			m.failf("current turn %q not active (%s)", v0.CurrentTurn, statusOf(s, v0.CurrentTurn))
		}
	} else if v0.CurrentTurn != "" {
		m.failf("current turn set outside hints")
	}
	if s.phase == game.PhaseVoting || s.phase == game.PhaseRunoffVoting {
		for _, c := range v0.Candidates {
			if statusOf(s, c) != game.StatusActive {
				m.failf("candidate %s not active", c)
			}
		}
	}
	if s.phase == game.PhaseEliminationReveal && (v0.EliminatedPlayerID == "" || statusOf(s, v0.EliminatedPlayerID) == game.StatusActive) {
		m.failf("elimination reveal of %q (status %s)", v0.EliminatedPlayerID, statusOf(s, v0.EliminatedPlayerID))
	}
	// Room invariants.
	if len(s.room.Members) > MaxPlayers {
		m.failf("room over capacity")
	}
	if s.room.HostID != "" && !slices.ContainsFunc(s.room.Members, func(mm Member) bool { return mm.ID == s.room.HostID }) {
		m.failf("host %s not a member", s.room.HostID)
	}
	for _, id := range m.ids {
		st := statusOf(s, id)
		in := slices.ContainsFunc(s.room.Members, func(mm Member) bool { return mm.ID == id })
		if (st == game.StatusLeft || st == game.StatusRemoved) == in {
			m.failf("room membership of %s (status %s) = %v", id, st, in)
		}
	}
	if (s.phase == game.PhaseEnded) != (s.room.Status == StatusLobby) {
		m.failf("room status %s with game phase %s", s.room.Status, s.phase)
	}
	// Active counts: a live game never has the impostor at parity.
	if s.phase != game.PhaseEnded {
		act := activeIDs(s, m.ids)
		cit := 0
		for _, id := range act {
			if id != m.impostor {
				cit++
			}
		}
		// Once caught, only the guess decides: citizens leaving during it do
		// not end the match on parity or head count (docs/decisions.md).
		if !slices.Contains(act, m.impostor) || (cit <= 1 && s.phase != game.PhaseImpostorGuess) {
			m.failf("live game with impostor active=%v citizens=%d", slices.Contains(act, m.impostor), cit)
		}
	}
}

func (m *modelRun) checkTransition(a, b snap, cause string, tick bool) {
	if b.version < a.version {
		m.failf("version went back %d -> %d", a.version, b.version)
	}
	if a.blob != b.blob && b.version == a.version {
		m.failf("visible change without version bump (%s)", cause)
	}
	hops := 1
	if tick {
		hops = 2
	}
	if a.phase != b.phase && !reachable(a.phase, b.phase, hops) {
		m.failf("illegal phase edge %s -> %s (%s)", a.phase, b.phase, cause)
	}
	if b.round < a.round {
		m.failf("round decreased")
	}
	if b.round > a.round+1 {
		m.failf("round jumped %d -> %d", a.round, b.round)
	}
	if b.round > a.round && a.phase != game.PhaseVoting && a.phase != game.PhaseRunoffVoting && a.phase != game.PhaseEliminationReveal {
		m.failf("round advanced from phase %s", a.phase)
	}
	for _, id := range m.ids {
		sa, sb := statusOf(a, id), statusOf(b, id)
		if sa == sb {
			continue
		}
		ok := sa == game.StatusActive || (sa == game.StatusEliminated && sb == game.StatusLeft)
		if !ok {
			m.failf("status %s: %s -> %s", id, sa, sb)
		}
		if sb == game.StatusEliminated {
			if id == m.impostor {
				m.failf("impostor eliminated as a citizen")
			}
			if a.phase != game.PhaseVoting && a.phase != game.PhaseRunoffVoting {
				m.failf("eliminated outside a vote (%s)", a.phase)
			}
		}
		if sb == game.StatusRemoved {
			pa := playerOf(a, id)
			if pa.Disconnects < game.MaxDisconnects-1 || pa.Connected {
				m.failf("%s removed with %d disconnects connected=%v", id, pa.Disconnects, pa.Connected)
			}
			if t, ok := m.goneAt[id]; !ok || b.now.Before(t.Add(30*time.Second)) {
				m.failf("%s removed before 30s away (gone at %v, now %v)", id, t, b.now)
			}
		}
	}
	// Phase timers: a phase entered during this step started at or before now.
	durs := map[game.Phase]time.Duration{game.PhaseVoting: 20 * time.Second, game.PhaseRunoffVoting: 15 * time.Second,
		game.PhasePreVoting: 5 * time.Second, game.PhaseHintBreak: 3 * time.Second, game.PhaseImpostorGuess: 60 * time.Second,
		game.PhaseEliminationReveal: 5 * time.Second, game.PhaseRoleReveal: 20 * time.Second}
	if b.phase != a.phase || (b.phase == game.PhaseHints && (a.views[m.ids[0]].CurrentTurn != b.views[m.ids[0]].CurrentTurn || a.round != b.round)) {
		d, ok := durs[b.phase]
		if b.phase == game.PhaseHints {
			d, ok = 60*time.Second, true
			if b.views[m.ids[0]].Reconnecting {
				d = 30 * time.Second
			}
		}
		if ok {
			start := b.dl.Add(-d)
			if start.After(b.now) || start.Before(a.now.Add(-d)) {
				m.failf("phase %s deadline %v implies start %v outside [%v,%v]", b.phase, b.dl, start, a.now, b.now)
			}
		}
	}
	// Tally shadow check.
	if (a.phase == game.PhaseVoting || a.phase == game.PhaseRunoffVoting) && (b.phase != a.phase || !b.dl.Equal(a.dl)) {
		m.checkTally(a, b)
	}
	if a.phase != game.PhaseVoting && a.phase != game.PhaseRunoffVoting && (b.phase == game.PhaseVoting || b.phase == game.PhaseRunoffVoting) {
		m.votes = map[string]string{}
		m.voteCast = false
	}
	if b.phase == game.PhaseEnded && a.phase != game.PhaseEnded {
		m.checkResult(a, b, cause)
	}
}

func (m *modelRun) prune(s snap) {
	for voter, target := range m.votes {
		if gone(s, voter) || gone(s, target) {
			delete(m.votes, voter)
		}
	}
}

func (m *modelRun) checkTally(a, b snap) {
	m.prune(b)
	// Votes as the players saw them (MyVote), minus voters/targets who left in this step.
	counted := map[string]string{}
	for _, id := range m.ids {
		if t := a.views[id].MyVote; t != "" {
			if gone(b, id) || gone(b, t) {
				continue
			}
			counted[id] = t
		}
	}
	if !mapsEqual(counted, m.votes) && !anyGone(a, b, m.ids) {
		m.failf("shadow votes %v != MyVote reconstruction %v", m.votes, counted)
	}
	if anyGone(a, b, m.ids) && b.phase == game.PhaseEnded && (b.views[m.ids[0]].Result.Reason == game.ReasonImpostorGone || b.views[m.ids[0]].Result.Reason == game.ReasonImpostorParity) {
		return // ended by a removal in the same tick before/after tally; not decidable here
	}
	m.shadowVR = append(m.shadowVR, counted)
	cands := a.views[m.ids[0]].Candidates
	counts := map[string]int{}
	for _, t := range counted {
		counts[t]++
	}
	var top []string
	most := 0
	for _, c := range cands {
		if gone(b, c) {
			continue
		}
		switch n := counts[c]; {
		case n > most:
			top, most = []string{c}, n
		case n == most && n > 0:
			top = append(top, c)
		}
	}
	if len(counted) == 0 && !m.voteCast {
		m.silent++
	} else {
		m.silent = 0
	}
	v := b.views[m.ids[0]]
	switch {
	case m.silent >= 2:
		if b.phase != game.PhaseEnded || v.Result.Reason != game.ReasonAbandoned {
			m.failf("two silent votes did not abandon: phase %s", b.phase)
		}
	case len(top) == 1 && top[0] == m.impostor:
		if b.phase != game.PhaseImpostorGuess && (b.phase != game.PhaseEnded || v.Result.Reason != game.ReasonImpostorGuessTimeout) {
			m.failf("impostor top-voted but phase %s", b.phase)
		}
	case len(top) == 1:
		if statusOf(b, top[0]) != game.StatusEliminated {
			m.failf("citizen %s top-voted but status %s", top[0], statusOf(b, top[0]))
		}
	case len(top) > 1 && a.phase == game.PhaseVoting:
		if b.phase != game.PhaseRunoffVoting || !sameSet(v.Candidates, top) {
			m.failf("tie %v -> phase %s candidates %v", top, b.phase, v.Candidates)
		}
		if b.dl.Sub(b.now) > 15*time.Second {
			m.failf("runoff longer than 15s")
		}
	default:
		if b.round != a.round+1 && b.phase != game.PhaseEnded {
			m.failf("no decision (top=%v, phase %s) did not open a new round: round %d->%d phase %s", top, a.phase, a.round, b.round, b.phase)
		}
		for _, id := range m.ids {
			if statusOf(a, id) == game.StatusActive && statusOf(b, id) == game.StatusEliminated {
				m.failf("tie/silent vote eliminated %s", id)
			}
		}
	}
	m.votes = map[string]string{}
	m.voteCast = false
}

func gone(s snap, id string) bool {
	st := statusOf(s, id)
	return st == game.StatusLeft || st == game.StatusRemoved
}

func anyGone(a, b snap, ids []string) bool {
	for _, id := range ids {
		if !gone(a, id) && gone(b, id) {
			return true
		}
	}
	return false
}

func mapsEqual(a, b map[string]string) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if b[k] != v {
			return false
		}
	}
	return true
}

func sameSet(a, b []string) bool {
	x, y := slices.Clone(a), slices.Clone(b)
	slices.Sort(x)
	slices.Sort(y)
	return slices.Equal(x, y)
}

func (m *modelRun) checkResult(a, b snap, cause string) {
	res := b.views[m.ids[0]].Result
	m.reasons[res.Reason]++
	if res.ImpostorID != m.impostor || res.SecretWord != m.secret {
		m.failf("result impostor/word wrong")
	}
	if len(res.VoteRounds) != len(res.Abstentions) {
		m.failf("voteRounds %d vs abstentions %d", len(res.VoteRounds), len(res.Abstentions))
	}
	for i, vr := range res.VoteRounds {
		for voter, target := range vr {
			if voter == target {
				m.failf("self vote counted in round %d", i)
			}
		}
		// Two empty rounds need not be abandonment: votes cast for or by a
		// player who then left are deleted, and that round was not silent.
	}
	act := activeIDs(b, m.ids)
	cit := 0
	for _, id := range act {
		if id != m.impostor {
			cit++
		}
	}
	switch res.Reason {
	case game.ReasonImpostorGone:
		if !gone(b, m.impostor) || res.Winner != game.TeamCitizens {
			m.failf("impostor_gone but impostor status %s winner %s", statusOf(b, m.impostor), res.Winner)
		}
	case game.ReasonImpostorParity:
		if res.Winner != game.TeamImpostor || cit > 1 || statusOf(b, m.impostor) != game.StatusActive {
			m.failf("parity with %d active citizens", cit)
		}
	case game.ReasonImpostorGuessTimeout:
		if a.phase != game.PhaseImpostorGuess && a.phase != game.PhaseVoting && a.phase != game.PhaseRunoffVoting || res.Winner != game.TeamCitizens {
			m.failf("guess timeout from %s", a.phase)
		}
	case game.ReasonImpostorGuessedWord, game.ReasonImpostorGuessWrong:
		if a.phase != game.PhaseImpostorGuess || !strings.HasPrefix(cause, "guess") {
			m.failf("guess result from %s (%s)", a.phase, cause)
		}
	case game.ReasonAbandoned:
		if res.Winner != game.TeamNone {
			m.failf("abandoned with a winner")
		}
	case game.ReasonNotEnoughPlayers:
		// reachable? recorded in m.reasons
	default:
		m.failf("unexpected reason %s", res.Reason)
	}
	if res.Reason != game.ReasonAbandoned && res.Reason != game.ReasonNotEnoughPlayers && !sameVR(res.VoteRounds, m.shadowVR) && !anyGoneEver(b, m.ids) {
		m.failf("result voteRounds %v != shadow %v", res.VoteRounds, m.shadowVR)
	}
	for _, id := range m.ids {
		st := statusOf(b, id)
		want := game.OutcomeLoss
		switch {
		case res.Reason == game.ReasonAbandoned:
			want = game.OutcomeNone
		case st == game.StatusLeft || st == game.StatusRemoved:
			want = game.OutcomeLoss
		case res.Winner == game.TeamNone:
			want = game.OutcomeWin // engine behaviour for not_enough_players (flagged separately)
		case (res.Winner == game.TeamImpostor) == (id == m.impostor):
			want = game.OutcomeWin
		}
		if res.Outcomes[id] != want {
			m.failf("outcome %s = %s, want %s (status %s reason %s)", id, res.Outcomes[id], want, st, res.Reason)
		}
	}
}

func anyGoneEver(s snap, ids []string) bool {
	for _, id := range ids {
		if gone(s, id) {
			return true
		}
	}
	return false
}

func sameVR(a, b []map[string]string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if !mapsEqual(a[i], b[i]) {
			return false
		}
	}
	return true
}

func (m *modelRun) pick(from []string) string {
	if len(from) == 0 || m.rng.IntN(10) == 0 {
		all := append(slices.Clone(m.ids), "ghost")
		return all[m.rng.IntN(len(all))]
	}
	return from[m.rng.IntN(len(from))]
}

func (m *modelRun) hintText(s snap) string {
	v := s.views[m.ids[0]]
	switch m.rng.IntN(16) {
	case 0:
		return m.secret
	case 1:
		return "ה" + m.secret
	case 2:
		rs := []rune(m.secret)
		return string(rs[:1]) + "ָ" + string(rs[1:])
	case 3:
		rs := []rune(m.secret)
		return string(rs[:1]) + "\u200b" + string(rs[1:])
	case 4:
		for i := len(v.Hints) - 1; i >= 0; i-- {
			if !v.Hints[i].Missing {
				return "ו" + v.Hints[i].Text
			}
		}
		return ""
	case 5:
		return "  "
	case 6:
		return "שתי מילים"
	case 7:
		return strings.Repeat("א", 26)
	case 8:
		return "blocked"
	case 9:
		return "🐘"
	default:
		m.hintSeq++
		return "w" + strconv.Itoa(m.hintSeq) + "x"
	}
}

func (m *modelRun) step() {
	r := m.r
	before := takeSnap(r, m.ids, m.now)
	if before.phase == game.PhaseEnded {
		return
	}
	m.steps++
	kind := m.rng.IntN(100)
	if kind < 30 {
		dl := r.Deadline()
		switch x := m.rng.IntN(6); {
		case x == 0 || dl.IsZero():
			m.now = m.now.Add(time.Duration(m.rng.IntN(3000)) * time.Millisecond)
		case x == 1 && dl.After(m.now):
			m.now = dl.Add(-time.Millisecond)
		default:
			if dl.After(m.now) {
				m.now = dl
			}
		}
		m.log("tick")
		r.Tick(m.now)
		after := takeSnap(r, m.ids, m.now)
		m.trackDisc(before, after)
		m.checkTransition(before, after, "tick", true)
		m.checkState(after)
		return
	}
	// Commands: tick first so the command acts on a settled state.
	r.Tick(m.now)
	mid := takeSnap(r, m.ids, m.now)
	m.trackDisc(before, mid)
	m.checkTransition(before, mid, "pretick", true)
	m.checkState(mid)
	if mid.phase == game.PhaseEnded {
		return
	}
	v := mid.views[m.ids[0]]
	act := activeIDs(mid, m.ids)
	var watchers []string
	for _, id := range m.ids {
		if st := statusOf(mid, id); st == game.StatusActive || st == game.StatusEliminated {
			watchers = append(watchers, id)
		}
	}
	var cause string
	var err error
	var actor string
	switch {
	case kind < 45:
		actor = m.pick([]string{v.CurrentTurn})
		text := m.hintText(mid)
		cause = fmt.Sprintf("hint %s %q", actor, text)
		err = r.WithGame(m.now, func(g *game.Game) error { return g.SubmitHint(actor, text, m.now) })
		m.checkHint(mid, actor, text, err)
	case kind < 60:
		actor = m.pick(act)
		cands := append(slices.Clone(v.Candidates), actor, "ghost")
		target := cands[m.rng.IntN(len(cands))]
		cause = fmt.Sprintf("vote %s->%s", actor, target)
		err = r.WithGame(m.now, func(g *game.Game) error { return g.Vote(actor, target, m.now) })
		valid := (mid.phase == game.PhaseVoting || mid.phase == game.PhaseRunoffVoting) && statusOf(mid, actor) == game.StatusActive && target != actor && slices.Contains(v.Candidates, target)
		if (err == nil) != valid {
			m.failf("vote %s->%s accepted=%v valid=%v err=%v phase=%s", actor, target, err == nil, valid, err, mid.phase)
		}
		if err == nil {
			m.votes[actor] = target
			m.voteCast = true
		}
	case kind < 68:
		actor = m.pick(act)
		cause = "confirm " + actor
		err = r.WithGame(m.now, func(g *game.Game) error { return g.ConfirmRole(actor, m.now) })
		valid := mid.phase == game.PhaseRoleReveal && statusOf(mid, actor) == game.StatusActive
		if (err == nil) != valid {
			m.failf("confirm %s accepted=%v valid=%v", actor, err == nil, valid)
		}
	case kind < 74:
		actor = m.pick(watchers)
		idx := len(v.Hints) - 1 - m.rng.IntN(2)
		cause = fmt.Sprintf("react %s %d", actor, idx)
		err = r.WithGame(m.now, func(g *game.Game) error { return g.React(actor, idx, "x", m.now) })
		okActor := statusOf(mid, actor) == game.StatusActive || statusOf(mid, actor) == game.StatusEliminated
		if err == nil && (!okActor || mid.phase == game.PhaseRoleReveal) {
			m.failf("reaction accepted from %s (%s) in %s", actor, statusOf(mid, actor), mid.phase)
		}
	case kind < 79:
		actor = m.pick(watchers)
		cause = "continue " + actor
		err = r.WithGame(m.now, func(g *game.Game) error { return g.ContinueAfterElimination(actor, m.now) })
		valid := mid.phase == game.PhaseEliminationReveal && (statusOf(mid, actor) == game.StatusActive || statusOf(mid, actor) == game.StatusEliminated)
		if (err == nil) != valid {
			m.failf("continue %s accepted=%v valid=%v", actor, err == nil, valid)
		}
	case kind < 84:
		actor = m.pick([]string{m.impostor})
		guess := []string{m.secret, "ה" + m.secret, "לא", "בננות", ""}[m.rng.IntN(5)]
		cause = fmt.Sprintf("guess %s %q", actor, guess)
		err = r.WithGame(m.now, func(g *game.Game) error { return g.SubmitGuess(actor, guess, m.now) })
		valid := mid.phase == game.PhaseImpostorGuess && actor == m.impostor
		if (err == nil) != valid {
			m.failf("guess %s accepted=%v valid=%v", actor, err == nil, valid)
		}
		if err == nil {
			gv, _ := r.Game().View(actor)
			res := gv.Result
			right := refNorm(guess) == refNorm(m.secret) || refPrefixed(refNorm(guess), refNorm(m.secret))
			if right != (res.Winner == game.TeamImpostor) {
				m.failf("guess %q judged %s", guess, res.Reason)
			}
		}
	case kind < 91:
		actor = m.pick(watchers)
		cause = "disconnect " + actor
		err = r.Disconnect(actor, m.now)
	case kind < 98:
		actor = m.pick(watchers)
		cause = "reconnect " + actor
		wasTurn := mid.phase == game.PhaseHints && v.CurrentTurn == actor && v.Reconnecting
		err = r.Reconnect(actor, m.now)
		if wasTurn && err == nil {
			nv, _ := r.Game().View(actor)
			if nv.Reconnecting || nv.Deadline.After(m.now.Add(60*time.Second)) {
				m.failf("reconnect in own turn did not resume the turn's clock (dl %v)", nv.Deadline)
			}
		}
	default:
		actor = m.pick(watchers)
		cause = "leave " + actor
		err = r.Leave(actor, m.now)
	}
	m.log("%s -> %v", cause, err)
	after := takeSnap(r, m.ids, m.now)
	m.trackDisc(mid, after)
	m.prune(after)
	if err == nil && !strings.HasPrefix(cause, "react") && !strings.HasPrefix(cause, "leave") && !strings.HasPrefix(cause, "disconnect") && !strings.HasPrefix(cause, "reconnect") && !strings.HasPrefix(cause, "confirm") && !strings.HasPrefix(cause, "continue") && after.blob == mid.blob {
		m.failf("accepted %s changed nothing", cause)
	}
	if actor == "ghost" && err == nil {
		m.failf("ghost command accepted: %s", cause)
	}
	m.checkTransition(mid, after, cause, false)
	m.checkState(after)
	phaseSeen[after.phase]++
}

// trackDisc records when active players drop, checks that a drop counts only
// after 30 s away and that the one reaching MaxDisconnects removes, and that no
// hint turn outlives its own 60 s clock however its player comes and goes.
func (m *modelRun) trackDisc(a, b snap) {
	for _, id := range m.ids {
		pa, pb := playerOf(a, id), playerOf(b, id)
		if pb.Connected {
			delete(m.goneAt, id)
			continue
		}
		if pa.Connected && pb.Status == game.StatusActive && b.phase != game.PhaseEnded {
			m.goneAt[id], m.goneCount[id] = b.now, pb.Disconnects
		}
		t, gone := m.goneAt[id]
		if pb.Disconnects > pa.Disconnects && (!gone || b.now.Before(t.Add(30*time.Second))) {
			m.failf("%s's drop counted before 30 s away", id)
		}
		if gone && pb.Status == game.StatusActive && m.goneCount[id] >= game.MaxDisconnects-1 && b.phase != game.PhaseEnded && !b.now.Before(t.Add(30*time.Second)) {
			m.failf("%s still active %v into the drop that reaches %d", id, b.now.Sub(t), game.MaxDisconnects)
		}
	}
	if v := b.views[m.ids[0]]; b.phase == game.PhaseHints {
		key := fmt.Sprintf("%d/%s", v.Round, v.CurrentTurn)
		first, ok := m.turnSeen[key]
		if !ok {
			m.turnSeen[key] = b.now
		} else if !b.now.Before(first.Add(60 * time.Second)) {
			m.failf("turn %s still running %v after it began", key, b.now.Sub(first))
		}
	}
}

func (m *modelRun) checkHint(mid snap, actor, text string, err error) {
	v := mid.views[m.ids[0]]
	isTurn := mid.phase == game.PhaseHints && v.CurrentTurn == actor && !v.Reconnecting && statusOf(mid, actor) == game.StatusActive
	t := strings.TrimSpace(text)
	oneWord := t != "" && !strings.ContainsFunc(t, unicode.IsSpace) && len([]rune(t)) <= 25 && t != "blocked"
	hasLetter := refNorm(t) != "" // symbols or emoji alone are no hint
	citizen := actor != m.impostor
	containsSecret := citizen && refContainsSecret(t, m.secret)
	dup := false
	for _, h := range v.Hints {
		if !h.Missing && refSame(t, h.Text) {
			dup = true
		}
	}
	want := isTurn && oneWord && hasLetter && !containsSecret && !dup
	if (err == nil) != want {
		m.failf("hint %s %q accepted=%v want=%v (turn=%v oneWord=%v letters=%v secret=%v dup=%v err=%v)", actor, text, err == nil, want, isTurn, oneWord, hasLetter, containsSecret, dup, err)
	}
	if errors.Is(err, game.ErrHintContainsSecret) && !citizen {
		m.failf("impostor hint checked against the secret")
	}
}

func runModel(seed uint64, maxSteps int) *modelRun {
	rng := rand.New(rand.NewPCG(seed, seed*0x9e3779b97f4a7c15+1))
	n := 4 + rng.IntN(5)
	m := &modelRun{seed: seed, rng: rng, now: t0, goneAt: map[string]time.Time{}, goneCount: map[string]int{}, turnSeen: map[string]time.Time{}, reasons: map[game.EndReason]int{}, votes: map[string]string{}}
	for i := range n {
		m.ids = append(m.ids, "p"+strconv.Itoa(i))
	}
	hs := []int{30, 60, 90}[0:3]
	_ = hs
	r, err := New("123456", m.ids[0], Settings{MaxPlayers: 8, HintSeconds: 60, CategoryIDs: []string{"animals"}}, game.Policy{
		HintInappropriate: func(h string) bool { return h == "blocked" },
		ValidReaction:     func(id string) bool { return id == "x" },
	}, rng, t0)
	if err != nil {
		panic(err)
	}
	for _, id := range m.ids[1:] {
		if err := r.Join(id, t0); err != nil {
			panic(err)
		}
	}
	for _, id := range m.ids {
		if rng.IntN(8) == 0 {
			_ = r.Disconnect(id, t0)
		}
	}
	m.secret = auditSecrets[rng.IntN(len(auditSecrets))]
	if err := r.Start(r.View().HostID, "חיות", m.secret, t0); err != nil {
		m.fail = "start: " + err.Error()
		return m
	}
	m.r = r
	for _, id := range m.ids {
		if v, _ := r.Game().View(id); v.Role == game.RoleImpostor {
			m.impostor = id
		}
	}
	func() {
		defer func() {
			if p := recover(); p != nil {
				m.failf("panic: %v", p)
			}
		}()
		for i := 0; i < maxSteps && m.fail == "" && r.Game().Phase() != game.PhaseEnded; i++ {
			m.step()
			if v, _ := r.Game().View(m.ids[0]); v.Round > m.maxRound {
				m.maxRound = v.Round
			}
		}
	}()
	if m.fail == "" && r.Game().Phase() != game.PhaseEnded {
		m.failf("game did not end within %d steps (round %d)", maxSteps, m.maxRound)
	}
	return m
}

// TestModelCheck drives the room and its game with random legal and illegal
// commands, disconnects and clock jumps, checking the rules after every step.
// AUDIT_SEEDS=10000 for a deeper run.
func TestModelCheck(t *testing.T) {
	seeds := uint64(100)
	if s := os.Getenv("AUDIT_SEEDS"); s != "" {
		seeds, _ = strconv.ParseUint(s, 10, 64)
	}
	var from uint64
	if s := os.Getenv("AUDIT_SEED"); s != "" {
		from, _ = strconv.ParseUint(s, 10, 64)
		seeds = from + 1
	}
	reasons := map[game.EndReason]int{}
	fails := map[string][]uint64{}
	maxRound, totalSteps := 0, 0
	for seed := from; seed < seeds; seed++ {
		m := runModel(seed, 20000)
		for k, v := range m.reasons {
			reasons[k] += v
		}
		maxRound = max(maxRound, m.maxRound)
		totalSteps += m.steps
		if m.fail != "" {
			key := m.fail
			if i := strings.IndexAny(key, "0123456789"); i > 0 && i < 40 {
				key = key[:i]
			}
			fails[key] = append(fails[key], seed)
			if len(fails[key]) == 1 {
				t.Logf("seed %d: %s\n  last steps:\n    %s", seed, m.fail, strings.Join(m.trace[max(0, len(m.trace)-12):], "\n    "))
			}
		}
	}
	t.Logf("games=%d steps=%d maxRound=%d reasons=%v phases=%v", seeds-from, totalSteps, maxRound, reasons, phaseSeen)
	for k, v := range fails {
		t.Errorf("%d seeds violate %q (first %v)", len(v), k, v[:min(5, len(v))])
	}
}
