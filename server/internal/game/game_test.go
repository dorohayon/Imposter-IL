package game

import (
	"errors"
	"fmt"
	"math/rand/v2"
	"slices"
	"strings"
	"testing"
	"time"
)

var t0 = time.Date(2026, 9, 14, 12, 0, 0, 0, time.UTC)

const secret = "פיל"

// testPolicy stands in for the open content and reaction rules.
func testPolicy() Policy {
	return Policy{
		HintInappropriate: func(hint string) bool { return hint == "blocked" },
		ValidReaction:     func(id string) bool { return id == "suspicious" },
	}
}

func ids(n int) []string {
	return []string{"p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8", "p9"}[:n]
}

func newGame(t *testing.T, n int) *Game {
	t.Helper()
	g, err := New(DefaultConfig(), testPolicy(), ids(n), "film_tv", secret, rand.New(rand.NewPCG(1, 2)), t0)
	if err != nil {
		t.Fatal(err)
	}
	return g
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func wantErr(t *testing.T, got, want error) {
	t.Helper()
	if !errors.Is(got, want) {
		t.Fatalf("error = %v, want %v", got, want)
	}
}

func wantPhase(t *testing.T, g *Game, want Phase) {
	t.Helper()
	if g.phase != want {
		t.Fatalf("phase = %s, want %s", g.phase, want)
	}
}

func confirmAll(t *testing.T, g *Game) {
	t.Helper()
	for _, id := range g.order {
		must(t, g.ConfirmRole(id, t0))
	}
	wantPhase(t, g, PhaseHints)
}

// toVoting plays every turn with a unique hint and returns the time voting opened.
func toVoting(t *testing.T, g *Game) time.Time {
	t.Helper()
	confirmAll(t, g)
	now := t0
	for i, id := range g.order {
		now = now.Add(time.Second)
		must(t, g.SubmitHint(id, "hint"+string(rune('a'+i)), now))
		// Every hint is held before the board moves on.
		if g.phase == PhaseHintBreak {
			now = now.Add(DefaultConfig().HintBreakDuration)
			g.Tick(now)
		}
	}
	// The finished board is held for a beat before the vote opens.
	wantPhase(t, g, PhasePreVoting)
	now = now.Add(DefaultConfig().PreVotingDuration)
	g.Tick(now)
	wantPhase(t, g, PhaseVoting)
	return now
}

// citizens are the citizens still playing. Once a match can vote people out,
// "not the impostor" is no longer the same as "still at the table".
func citizens(g *Game) []string {
	return slices.DeleteFunc(g.activeIDs(), func(id string) bool { return id == g.impostor })
}

// voteFor makes every other active player vote for target.
func voteAllFor(t *testing.T, g *Game, target string, now time.Time) {
	t.Helper()
	for _, id := range g.activeIDs() {
		if id != target {
			must(t, g.Vote(id, target, now))
		}
	}
	if target != g.impostor {
		return
	}
	// the impostor cannot vote for themself; send them elsewhere
	must(t, g.Vote(target, citizens(g)[0], now))
}

func TestNewValidatesSetup(t *testing.T) {
	cfg, p, rng := DefaultConfig(), testPolicy(), rand.New(rand.NewPCG(1, 2))
	cases := map[string]func() error{
		"three players": func() error { _, err := New(cfg, p, ids(3), "c", "w", rng, t0); return err },
		"nine players":  func() error { _, err := New(cfg, p, ids(9), "c", "w", rng, t0); return err },
		"duplicate id": func() error {
			_, err := New(cfg, p, []string{"a", "b", "c", "a"}, "c", "w", rng, t0)
			return err
		},
		"no word":     func() error { _, err := New(cfg, p, ids(4), "c", "", rng, t0); return err },
		"no category": func() error { _, err := New(cfg, p, ids(4), "", "w", rng, t0); return err },
		"no policy":   func() error { _, err := New(cfg, Policy{}, ids(4), "c", "w", rng, t0); return err },
		"no rng":      func() error { _, err := New(cfg, p, ids(4), "c", "w", nil, t0); return err },
		"zero hint":   func() error { _, err := New(Config{}, p, ids(4), "c", "w", rng, t0); return err },
	}
	for name, f := range cases {
		t.Run(name, func(t *testing.T) { wantErr(t, f(), ErrInvalidSetup) })
	}
	for _, n := range []int{4, 8} {
		if _, err := New(cfg, p, ids(n), "c", "w", rng, t0); err != nil {
			t.Fatalf("%d players: %v", n, err)
		}
	}
}

func TestNewPicksRandomImpostorAndOrder(t *testing.T) {
	impostors, orders := map[string]bool{}, map[string]bool{}
	for seed := range uint64(40) {
		g, err := New(DefaultConfig(), testPolicy(), ids(6), "c", "w", rand.New(rand.NewPCG(seed, seed)), t0)
		must(t, err)
		impostors[g.impostor] = true
		orders[strings.Join(g.order, ",")] = true
	}
	if len(impostors) < 4 || len(orders) < 20 {
		t.Fatalf("not random enough: %d impostors, %d orders", len(impostors), len(orders))
	}
}

func TestOnlyCitizensSeeTheSecretWord(t *testing.T) {
	g := newGame(t, 4)
	for _, id := range g.order {
		v, err := g.View(id)
		must(t, err)
		if v.Category != "film_tv" {
			t.Fatalf("%s category = %q", id, v.Category)
		}
		isImpostor := id == g.impostor
		if isImpostor != (v.Role == RoleImpostor) || isImpostor != (v.SecretWord == "") {
			t.Fatalf("%s: role %s, word %q", id, v.Role, v.SecretWord)
		}
	}
	must(t, g.Leave(g.impostor, t0))
	v, _ := g.View(g.impostor)
	if v.SecretWord != secret || v.Result.SecretWord != secret {
		t.Fatalf("word not revealed after the end: %+v", v)
	}
}

func TestViewReturnsResultSnapshot(t *testing.T) {
	g := newGame(t, 4)
	now := toVoting(t, g)
	// A round nobody votes in no longer ends anything, so reach the end the
	// way a table does: catch the impostor, who then guesses wrong.
	for _, id := range g.activeIDs() {
		if id != g.impostor {
			must(t, g.Vote(id, g.impostor, now))
		}
	}
	now = now.Add(20 * time.Second)
	g.Tick(now)
	must(t, g.SubmitGuess(g.impostor, "לאיודע", now))

	v, _ := g.View(g.impostor)
	v.Result.Winner = TeamImpostor
	v.Result.Outcomes[g.impostor] = OutcomeWin
	v.Result.VoteRounds[0][g.order[0]] = g.order[1]

	next, _ := g.View(g.impostor)
	if next.Result.Winner != TeamCitizens || next.Result.Outcomes[g.impostor] != OutcomeLoss || len(next.Result.VoteRounds[0]) != 3 {
		t.Fatalf("mutating result view changed game result: %+v", next.Result)
	}
}

func TestRoleRevealWaitsForConnectedPlayers(t *testing.T) {
	g := newGame(t, 4)
	must(t, g.Disconnect(g.order[3], t0))
	for _, id := range g.order[:2] {
		must(t, g.ConfirmRole(id, t0))
	}
	wantPhase(t, g, PhaseRoleReveal)
	must(t, g.ConfirmRole(g.order[2], t0))
	wantPhase(t, g, PhaseHints)
	wantErr(t, g.ConfirmRole(g.order[0], t0), ErrWrongPhase)
}

func TestMarkOfflineAtStartIsNotACountedDisconnect(t *testing.T) {
	g := newGame(t, 4)
	offline := g.order[0]
	must(t, g.MarkOffline(offline))
	wantErr(t, g.MarkOffline("nobody"), ErrUnknownPlayer)

	// Role reveal ends once the connected players confirm, and the offline
	// player's turn waits for a reconnect.
	for _, id := range g.order[1:] {
		must(t, g.ConfirmRole(id, t0))
	}
	wantPhase(t, g, PhaseHints)
	if !g.reconnecting || g.players[offline].disconnects != 0 {
		t.Fatalf("reconnecting = %v, disconnects = %d", g.reconnecting, g.players[offline].disconnects)
	}
	wantErr(t, g.MarkOffline(g.order[1]), ErrWrongPhase)
}

func TestRoleRevealTimesOutAfterTwentySeconds(t *testing.T) {
	g := newGame(t, 4)
	if want := t0.Add(20 * time.Second); !g.Deadline().Equal(want) {
		t.Fatalf("role reveal deadline = %v, want %v", g.Deadline(), want)
	}
	must(t, g.ConfirmRole(g.order[0], t0))
	g.Tick(t0.Add(19 * time.Second))
	wantPhase(t, g, PhaseRoleReveal)
	g.Tick(t0.Add(20 * time.Second))
	wantPhase(t, g, PhaseHints)
	if want := t0.Add(80 * time.Second); !g.Deadline().Equal(want) {
		t.Fatalf("first turn deadline = %v, want %v", g.Deadline(), want)
	}
}

func TestHintTurnsFollowOrderWithSixtySeconds(t *testing.T) {
	g := newGame(t, 4)
	confirmAll(t, g)
	if want := t0.Add(60 * time.Second); !g.Deadline().Equal(want) {
		t.Fatalf("deadline = %v, want %v", g.Deadline(), want)
	}
	wantErr(t, g.SubmitHint(g.order[1], "early", t0), ErrNotYourTurn)
	must(t, g.SubmitHint(g.order[0], "גדול", t0.Add(3*time.Second)))

	// The hint shows at once, and is held so the table can read it before the
	// next turn takes the screen.
	v, _ := g.View(g.order[2])
	if v.Phase != PhaseHintBreak || len(v.Hints) != 1 || v.Hints[0].Text != "גדול" {
		t.Fatalf("hint not held for reading: %+v", v)
	}
	if want := t0.Add(6 * time.Second); !g.Deadline().Equal(want) {
		t.Fatalf("hint break deadline = %v, want %v", g.Deadline(), want)
	}

	g.Tick(t0.Add(6 * time.Second))
	v, _ = g.View(g.order[2])
	if v.CurrentTurn != g.order[1] {
		t.Fatalf("next turn did not start: %+v", v)
	}
	if want := t0.Add(66 * time.Second); !g.Deadline().Equal(want) {
		t.Fatalf("next turn deadline = %v, want %v", g.Deadline(), want)
	}
}

func TestMissedHintIsMarkedAndPlayerStays(t *testing.T) {
	g := newGame(t, 4)
	confirmAll(t, g)
	g.Tick(t0.Add(60 * time.Second))
	if h := g.hints[0]; !h.Missing || h.PlayerID != g.order[0] {
		t.Fatalf("hint = %+v, want missing for %s", h, g.order[0])
	}
	if g.order[g.turn] != g.order[1] || g.players[g.order[0]].status != StatusActive {
		t.Fatal("turn did not move on or player was removed")
	}
	// a late hint from the expired turn is rejected
	wantErr(t, g.SubmitHint(g.order[0], "late", t0.Add(16*time.Second)), ErrNotYourTurn)
}

func TestHintValidation(t *testing.T) {
	g := newGame(t, 4)
	g.order = append([]string{g.impostor}, citizens(g)...)
	confirmAll(t, g)
	must(t, g.SubmitHint(g.order[0], "חדק", t0))
	g.Tick(t0.Add(3 * time.Second)) // past the hold on that hint
	cur := g.order[1]
	cases := []struct {
		hint string
		want error
	}{
		{"   ", ErrHintEmpty},
		{"שתי מילים", ErrHintNotOneWord},
		{strings.Repeat("א", 26), ErrHintTooLong},
		{"blocked", ErrHintInappropriate},
		{"פילים", ErrHintContainsSecret},
		{"הפִּיל", ErrHintContainsSecret},
		{"חדק", ErrHintDuplicate},
		{"והחדק", ErrHintDuplicate},
	}
	for _, c := range cases {
		wantErr(t, g.SubmitHint(cur, c.hint, t0), c.want)
	}
	if len(g.hints) != 1 || g.order[g.turn] != cur {
		t.Fatal("a blocked hint must not be shown or end the turn")
	}
	must(t, g.SubmitHint(cur, " "+strings.Repeat("א", 25)+" ", t0))
}

func TestImpostorHintIsNotCheckedAgainstTheSecret(t *testing.T) {
	g := newGame(t, 4)
	g.order = append([]string{g.impostor}, citizens(g)...)
	confirmAll(t, g)
	must(t, g.SubmitHint(g.impostor, "הפיל", t0))
	g.Tick(t0.Add(3 * time.Second)) // past the hold on that hint
	// a citizen using the word is still blocked
	wantErr(t, g.SubmitHint(g.order[1], secret, t0.Add(3*time.Second)),
		ErrHintContainsSecret)
}

func TestReactionsAreUnlimitedDuringNextTurn(t *testing.T) {
	g := newGame(t, 4)
	confirmAll(t, g)
	must(t, g.React(g.order[1], 0, "suspicious", t0))
	must(t, g.SubmitHint(g.order[0], "גדול", t0))
	if n := g.hints[0].Reactions["suspicious"]; n != 1 {
		t.Fatalf("pre-hint reaction = %d, want 1", n)
	}
	// Reacting works while the hint is held, and after the next turn opens.
	for range 5 {
		must(t, g.React(g.order[2], 0, "suspicious", t0))
	}
	g.Tick(t0.Add(3 * time.Second))
	wantErr(t, g.React(g.order[2], 0, "free text", t0), ErrInvalidReaction)
	if n := g.hints[0].Reactions["suspicious"]; n != 6 {
		t.Fatalf("reactions = %d, want 6 (1 before hint + 5 during hold)", n)
	}
	if g.order[g.turn] != g.order[1] {
		t.Fatal("reactions must not block the next turn")
	}
}

func TestPreHintReactionsBeforeFirstHintOfLaterRound(t *testing.T) {
	g := newGame(t, 4)
	confirmAll(t, g)
	must(t, g.SubmitHint(g.order[0], "ראשון", t0))
	g.Tick(t0.Add(3 * time.Second))
	g.round = 2
	g.startTurn(0, t0.Add(3*time.Second))
	last := len(g.hints) - 1
	must(t, g.React(g.order[1], last, "suspicious", t0.Add(3*time.Second)))
	if g.hints[last].Reactions != nil {
		t.Fatalf("reaction must not attach to the previous round's hint: %+v", g.hints[last].Reactions)
	}
	if g.pendingReactions["suspicious"] != 1 {
		t.Fatalf("pending = %v, want one suspicious", g.pendingReactions)
	}
	must(t, g.SubmitHint(g.order[0], "שני", t0.Add(3*time.Second)))
	var got *Hint
	for i := range g.hints {
		if g.hints[i].Round == 2 && g.hints[i].Text == "שני" {
			got = &g.hints[i]
			break
		}
	}
	if got == nil || got.Reactions["suspicious"] != 1 {
		t.Fatalf("round-2 hint reactions = %+v, want suspicious:1", got)
	}
}

func TestVoting(t *testing.T) {
	g := newGame(t, 4)
	now := toVoting(t, g)
	if want := now.Add(20 * time.Second); !g.Deadline().Equal(want) {
		t.Fatalf("vote deadline = %v, want %v", g.Deadline(), want)
	}
	a, b := g.order[0], g.order[1]
	wantErr(t, g.Vote(a, a, now), ErrSelfVote)
	wantErr(t, g.Vote(a, "nobody", now), ErrInvalidVoteTarget)
	must(t, g.Vote(a, b, now))

	if v, _ := g.View(b); v.MyVote != "" || v.Result != nil {
		t.Fatal("votes must stay hidden until the end")
	}
	// voting does not end early even when everyone voted
	voteAllFor(t, g, g.impostor, now)
	wantPhase(t, g, PhaseVoting)
}

func TestLastVoteBeforeDeadlineCounts(t *testing.T) {
	g := newGame(t, 4)
	now := toVoting(t, g)
	c := citizens(g)
	voteAllFor(t, g, c[0], now)
	voteAllFor(t, g, g.impostor, now.Add(19*time.Second))
	wantErr(t, g.Vote(c[1], c[0], now.Add(20*time.Second)), ErrWrongPhase)
	wantPhase(t, g, PhaseImpostorGuess)
}

// citizensWin catches the impostor and lets them fail the guess: the ordinary
// way a match ends once one vote no longer finishes it.
func citizensWin(t *testing.T, g *Game, now time.Time) time.Time {
	t.Helper()
	for _, id := range g.activeIDs() {
		if id != g.impostor {
			must(t, g.Vote(id, g.impostor, now))
		}
	}
	now = now.Add(20 * time.Second)
	g.Tick(now)
	wantPhase(t, g, PhaseImpostorGuess)
	must(t, g.SubmitGuess(g.impostor, "לאיודע", now))
	return now
}

func continueEliminationAllWatchers(t *testing.T, g *Game, now time.Time) {
	t.Helper()
	for _, id := range g.PlayerIDs() {
		p := g.players[id]
		if (p.status == StatusActive || p.status == StatusEliminated) && p.connected {
			must(t, g.ContinueAfterElimination(id, now))
		}
	}
}

func TestEliminationRevealOneTapDoesNotAdvance(t *testing.T) {
	g := newGame(t, 5)
	now := toVoting(t, g)
	out := citizens(g)[0]
	voteAllFor(t, g, out, now)
	now = now.Add(20 * time.Second)
	g.Tick(now)
	wantPhase(t, g, PhaseEliminationReveal)
	must(t, g.ContinueAfterElimination(g.order[1], now))
	wantPhase(t, g, PhaseEliminationReveal)
}

func TestEliminationRevealCanContinueEarly(t *testing.T) {
	g := newGame(t, 5)
	now := toVoting(t, g)
	out := citizens(g)[0]
	voteAllFor(t, g, out, now)
	now = now.Add(20 * time.Second)
	g.Tick(now)
	wantPhase(t, g, PhaseEliminationReveal)
	v, _ := g.View(out)
	if v.EliminatedPlayerID != out {
		t.Fatalf("eliminated = %q, want %q", v.EliminatedPlayerID, out)
	}
	continueEliminationAllWatchers(t, g, now)
	wantPhase(t, g, PhaseHints)
	if g.round != 2 {
		t.Fatalf("round = %d, want 2", g.round)
	}
}

func TestVotingOutACitizenStartsAnotherRound(t *testing.T) {
	g := newGame(t, 5) // four citizens and an impostor
	now := toVoting(t, g)
	out := citizens(g)[0]
	voteAllFor(t, g, out, now)
	now = now.Add(20 * time.Second)
	g.Tick(now)

	if g.result != nil {
		t.Fatalf("the match ended on one vote: %+v", g.result)
	}
	if got := g.players[out].status; got != StatusEliminated {
		t.Fatalf("status = %q, want eliminated", got)
	}
	wantPhase(t, g, PhaseEliminationReveal)
	now = now.Add(DefaultConfig().EliminationRevealDuration)
	g.Tick(now)
	if g.round != 2 {
		t.Fatalf("round = %d, want 2", g.round)
	}
	wantPhase(t, g, PhaseHints)
	// The eliminated citizen has no turn in the new round.
	if g.order[g.turn] == out {
		t.Fatal("the turn went to a player who was voted out")
	}
	// The board keeps what was said, labelled by the round it was said in.
	if len(g.hints) != 5 {
		t.Fatalf("hints = %d, want the first round kept", len(g.hints))
	}
	for _, h := range g.hints {
		if h.Round != 1 {
			t.Fatalf("hint %q carries round %d", h.Text, h.Round)
		}
	}
}

func TestARoundNobodyVotesInEliminatesNobody(t *testing.T) {
	g := newGame(t, 4)
	now := toVoting(t, g)
	g.Tick(now.Add(20 * time.Second))
	if g.result != nil {
		t.Fatalf("silence ended the match: %+v", g.result)
	}
	if g.round != 2 {
		t.Fatalf("round = %d, want 2", g.round)
	}
	for _, id := range g.order {
		if g.players[id].status != StatusActive {
			t.Fatalf("%s was voted out by nobody voting", id)
		}
	}
}

func TestImpostorGuess(t *testing.T) {
	caught := func(t *testing.T) (*Game, time.Time) {
		g := newGame(t, 6)
		now := toVoting(t, g)
		voteAllFor(t, g, g.impostor, now)
		now = now.Add(20 * time.Second)
		g.Tick(now)
		wantPhase(t, g, PhaseImpostorGuess)
		if want := now.Add(60 * time.Second); !g.Deadline().Equal(want) {
			t.Fatalf("guess deadline = %v, want %v", g.Deadline(), want)
		}
		return g, now
	}

	t.Run("correct guess", func(t *testing.T) {
		g, now := caught(t)
		wantErr(t, g.SubmitGuess(citizens(g)[0], secret, now), ErrNotImpostor)
		must(t, g.SubmitGuess(g.impostor, " "+secret, now))
		wantResult(t, g, TeamImpostor, ReasonImpostorGuessedWord)
	})
	t.Run("normalized guess with prefix", func(t *testing.T) {
		g, now := caught(t)
		must(t, g.SubmitGuess(g.impostor, "הַפִּיל", now))
		wantResult(t, g, TeamImpostor, ReasonImpostorGuessedWord)
	})
	t.Run("wrong guess", func(t *testing.T) {
		g, now := caught(t)
		must(t, g.SubmitGuess(g.impostor, "נמר", now))
		wantResult(t, g, TeamCitizens, ReasonImpostorGuessWrong)
		for _, id := range citizens(g) {
			if g.result.Outcomes[id] != OutcomeWin {
				t.Fatalf("citizen %s must win", id)
			}
		}
		wantErr(t, g.SubmitGuess(g.impostor, secret, now), ErrWrongPhase)
	})
	t.Run("timeout", func(t *testing.T) {
		g, now := caught(t)
		g.Tick(now.Add(60 * time.Second))
		wantResult(t, g, TeamCitizens, ReasonImpostorGuessTimeout)
	})
}

func TestAllRemainingCitizensWinEvenWithWrongVotes(t *testing.T) {
	g := newGame(t, 5)
	now := toVoting(t, g)
	c := citizens(g)
	voteAllFor(t, g, g.impostor, now)
	must(t, g.Vote(c[0], c[1], now)) // wrong vote, still a majority on the impostor
	g.Tick(now.Add(20 * time.Second))
	must(t, g.SubmitGuess(g.impostor, "wrong", now.Add(21*time.Second)))
	wantResult(t, g, TeamCitizens, ReasonImpostorGuessWrong)
	if g.result.Outcomes[c[0]] != OutcomeWin || g.result.Outcomes[g.impostor] != OutcomeLoss {
		t.Fatalf("outcomes = %v", g.result.Outcomes)
	}
	if len(g.result.VoteRounds) != 1 || g.result.VoteRounds[0][c[0]] != c[1] {
		t.Fatalf("vote breakdown = %v", g.result.VoteRounds)
	}
	if g.result.Abstentions[0] != 0 { // everyone voted
		t.Fatalf("abstentions = %v, want 0", g.result.Abstentions)
	}
}

func TestAbstentionsCountActivePlayersWhoDidNotVote(t *testing.T) {
	g := newGame(t, 4)
	now := toVoting(t, g)
	c := citizens(g)
	must(t, g.Vote(c[0], g.impostor, now))
	must(t, g.Disconnect(c[1], now)) // a disconnected vote would not count either
	g.Tick(now.Add(20 * time.Second))
	must(t, g.SubmitGuess(g.impostor, "wrong", now.Add(21*time.Second)))
	// Four active players, one counted vote.
	if got := g.result.Abstentions; len(got) != 1 || got[0] != 3 {
		t.Fatalf("abstentions = %v, want [3]", got)
	}
}

func TestTieGoesToRunoffAmongTiedOnly(t *testing.T) {
	g := newGame(t, 4)
	now := toVoting(t, g)
	c := citizens(g) // three citizens
	must(t, g.Vote(c[0], c[1], now))
	must(t, g.Vote(c[1], g.impostor, now))
	g.Tick(now.Add(20 * time.Second))
	wantPhase(t, g, PhaseRunoffVoting)
	if want := []string{c[1], g.impostor}; !sameSet(g.candidates, want) {
		t.Fatalf("runoff candidates = %v, want %v", g.candidates, want)
	}
	now = now.Add(20 * time.Second)
	if want := now.Add(15 * time.Second); !g.Deadline().Equal(want) {
		t.Fatalf("runoff deadline = %v, want %v", g.Deadline(), want)
	}
	if v, _ := g.View(c[0]); v.MyVote != "" {
		t.Fatal("runoff starts with fresh votes")
	}
	// The runoff shows how the tie happened.
	if v, _ := g.View(c[0]); v.PreviousVotes[c[1]] != 1 ||
		v.PreviousVotes[g.impostor] != 1 || len(v.PreviousVotes) != 2 {
		t.Fatalf("previous votes = %v, want one each for the tied players", v.PreviousVotes)
	}
	if v, _ := g.View(c[0]); v.Phase == PhaseVoting {
		t.Fatal("phase should be runoff")
	}
	wantErr(t, g.Vote(c[0], c[2], now), ErrInvalidVoteTarget)

	t.Run("a runoff that ties again eliminates nobody", func(t *testing.T) {
		must(t, g.Vote(c[0], c[1], now))
		must(t, g.Vote(c[2], g.impostor, now))
		g.Tick(now.Add(15 * time.Second))
		if g.result != nil {
			t.Fatalf("a second tie ended the match: %+v", g.result)
		}
		if g.round != 2 {
			t.Fatalf("round = %d, want 2", g.round)
		}
		wantPhase(t, g, PhaseHints)
		for _, id := range g.order {
			if g.players[id].status != StatusActive {
				t.Fatalf("%s was voted out by a tie", id)
			}
		}
		if len(g.voteRounds) != 2 {
			t.Fatalf("vote rounds = %d, want both kept", len(g.voteRounds))
		}
	})
}

func TestRunoffCatchesImpostor(t *testing.T) {
	g := newGame(t, 4)
	now := toVoting(t, g)
	c := citizens(g)
	must(t, g.Vote(c[0], c[1], now))
	must(t, g.Vote(c[1], g.impostor, now))
	now = now.Add(20 * time.Second)
	g.Tick(now)
	must(t, g.Vote(c[0], g.impostor, now))
	g.Tick(now.Add(15 * time.Second))
	wantPhase(t, g, PhaseImpostorGuess)
}

func TestDisconnectOnTurnSkipsAfterThirtySeconds(t *testing.T) {
	g := newGame(t, 4)
	confirmAll(t, g)
	p := g.order[0]
	must(t, g.Disconnect(p, t0.Add(5*time.Second)))
	if !g.reconnecting || !g.Deadline().Equal(t0.Add(35*time.Second)) || g.players[p].disconnects != 0 {
		t.Fatalf("want 30s reconnect window and no strike yet, got deadline %v", g.Deadline())
	}
	g.Tick(t0.Add(35 * time.Second))
	if !g.hints[0].Missing || g.players[p].status != StatusActive || g.order[g.turn] != g.order[1] {
		t.Fatal("first disconnect must skip the turn and keep the player")
	}
	if g.players[p].disconnects != 1 {
		t.Fatalf("disconnects = %d, want 1 after 30 s away", g.players[p].disconnects)
	}
}

func TestTurnStartingWhileDisconnectedWaitsForReconnect(t *testing.T) {
	g := newGame(t, 4)
	must(t, g.Disconnect(g.order[1], t0))
	confirmAll(t, g)
	must(t, g.SubmitHint(g.order[0], "גדול", t0.Add(time.Second)))
	g.Tick(t0.Add(4 * time.Second)) // past the hold on that hint
	if !g.reconnecting {
		t.Fatal("turn of a disconnected player must wait for reconnect")
	}
	wantErr(t, g.SubmitHint(g.order[1], "x", t0.Add(2*time.Second)), ErrNotYourTurn)
	turnEnds := g.turnDeadline
	must(t, g.Reconnect(g.order[1], t0.Add(10*time.Second)))
	if g.reconnecting || !g.Deadline().Equal(turnEnds) || !turnEnds.Before(t0.Add(70*time.Second)) {
		t.Fatalf("reconnect must resume the turn's own clock, deadline %v", g.Deadline())
	}
	must(t, g.SubmitHint(g.order[1], "אפור", t0.Add(11*time.Second)))
}

func TestThirdDisconnectRemovesWithLoss(t *testing.T) {
	g := newGame(t, 5)
	confirmAll(t, g)
	p, now := g.order[0], t0
	// Each drop counts once the player has been away 30 s.
	for range MaxDisconnects - 1 {
		must(t, g.Disconnect(p, now))
		now = now.Add(30 * time.Second)
		g.Tick(now)
		must(t, g.Reconnect(p, now))
	}
	if g.players[p].disconnects != MaxDisconnects-1 || g.players[p].status != StatusActive {
		t.Fatalf("disconnects = %d, status %s", g.players[p].disconnects, g.players[p].status)
	}
	must(t, g.Disconnect(p, now))
	g.Tick(now.Add(30 * time.Second))

	if g.players[p].status != StatusRemoved {
		t.Fatalf("status = %s, want removed", g.players[p].status)
	}
	wantErr(t, g.Reconnect(p, now.Add(31*time.Second)), ErrPlayerNotActive)
	if p == g.impostor {
		wantResult(t, g, TeamCitizens, ReasonImpostorGone)
	} else {
		wantPhase(t, g, PhaseHints)
		if g.order[g.turn] == p {
			t.Fatal("a removed player must not hold the turn")
		}
	}
	if v, _ := g.View(p); v.Players[0].Status != StatusRemoved {
		t.Fatal("removed player must still receive a view")
	}
}

func TestSimultaneousRemovalDeadlinesAreAppliedBeforeGameEnds(t *testing.T) {
	g := newGame(t, 5)
	g.order = append([]string{g.impostor}, citizens(g)...)
	confirmAll(t, g)
	removedCitizen := g.order[1]
	removeAt := t0.Add(time.Second)
	for _, id := range []string{g.impostor, removedCitizen} {
		p := g.players[id]
		p.connected = false
		p.disconnects = MaxDisconnects - 1
		p.strikeAt = removeAt // the third drop counts now
	}

	g.Tick(removeAt)

	wantResult(t, g, TeamCitizens, ReasonImpostorGone)
	for _, id := range []string{g.impostor, removedCitizen} {
		if g.players[id].status != StatusRemoved || g.result.Outcomes[id] != OutcomeLoss {
			t.Fatalf("%s = %s/%s, want removed/loss", id, g.players[id].status, g.result.Outcomes[id])
		}
	}
}

// A blip on the network is not a strike: a drop counts only once the player
// has been away for 30 seconds, in any phase.
func TestADropCountsOnlyIfThePlayerStaysAway(t *testing.T) {
	g := newGame(t, 5)
	p := citizens(g)[0]
	must(t, g.Disconnect(p, t0)) // role reveal, back within 30 s
	must(t, g.Reconnect(p, t0.Add(5*time.Second)))
	if g.players[p].disconnects != 0 {
		t.Fatalf("disconnects = %d after a 5 s blip, want 0", g.players[p].disconnects)
	}
	now := toVoting(t, g)
	must(t, g.Disconnect(p, now)) // voting, away for good
	g.Tick(now.Add(30 * time.Second))
	if g.players[p].disconnects != 1 {
		t.Fatalf("disconnects = %d, want 1", g.players[p].disconnects)
	}
	g.Tick(now.Add(time.Minute))
	if g.players[p].status != StatusActive {
		t.Fatal("a second disconnect outside the turn must not remove the player")
	}
	must(t, g.Reconnect(p, now.Add(time.Minute)))
	// End the match before the last disconnect, which must not be counted.
	must(t, g.Leave(g.impostor, now.Add(time.Minute)))
	must(t, g.Disconnect(p, now.Add(time.Minute))) // ended: not counted
	g.Tick(now.Add(2 * time.Minute))
	if g.players[p].disconnects != 1 {
		t.Fatal("disconnects after the game ended must not count")
	}
}

func TestThirdDisconnectOutsideTurnRemovesAfterThirtySeconds(t *testing.T) {
	setup := func(t *testing.T) (*Game, string, time.Time) {
		g := newGame(t, 5)
		p := citizens(g)[0]
		g.players[p].disconnects = MaxDisconnects - 1
		now := toVoting(t, g)
		voteAllFor(t, g, g.impostor, now) // voting ends at +20s, guess runs until +80s
		must(t, g.Disconnect(p, now))
		g.Tick(now.Add(20 * time.Second))
		if want := now.Add(30 * time.Second); !g.Deadline().Equal(want) {
			t.Fatalf("next deadline = %v, want removal at %v", g.Deadline(), want)
		}
		return g, p, now
	}

	t.Run("not back in time", func(t *testing.T) {
		g, p, now := setup(t)
		g.Tick(now.Add(30 * time.Second))
		if g.players[p].status != StatusRemoved {
			t.Fatalf("status = %s, want removed", g.players[p].status)
		}
		wantPhase(t, g, PhaseImpostorGuess)
		g.Tick(now.Add(80 * time.Second))
		if g.result.Outcomes[p] != OutcomeLoss {
			t.Fatal("a removed citizen loses even when citizens win")
		}
	})
	t.Run("back in time", func(t *testing.T) {
		g, p, now := setup(t)
		must(t, g.Reconnect(p, now.Add(29*time.Second)))
		g.Tick(now.Add(time.Hour))
		if g.players[p].status != StatusActive {
			t.Fatal("a player who returned in time stays in the game")
		}
	})
}

// A choice already made survives a moment of bad signal. Dropping it meant a
// phone losing the network between the tap and the timer closing threw the
// vote away, which on a phone is a normal thing to happen.
func TestAVoteSurvivesTheVoterDroppingOffline(t *testing.T) {
	g := newGame(t, 4)
	now := toVoting(t, g)
	c := citizens(g)
	must(t, g.Vote(c[0], g.impostor, now))
	must(t, g.Vote(c[1], c[2], now))
	must(t, g.Vote(c[2], c[1], now))
	// Two of them drop off the line after choosing.
	must(t, g.Disconnect(c[1], now.Add(time.Second)))
	must(t, g.Disconnect(c[2], now.Add(time.Second)))
	g.Tick(now.Add(20 * time.Second))

	// All three votes counted, so c[1] and c[2] tie and go to a runoff — the
	// impostor is not simply handed the round by the other two vanishing.
	wantPhase(t, g, PhaseRunoffVoting)
	if len(g.voteRounds[0]) != 3 {
		t.Fatalf("counted %d votes, want all three", len(g.voteRounds[0]))
	}
	// One abstention, and it is the impostor, who never voted at all — not the
	// two who chose and then lost the network.
	if g.abstentions[0] != 1 {
		t.Fatalf("abstentions = %d, want only the impostor who never voted", g.abstentions[0])
	}
	for _, id := range []string{c[1], c[2]} {
		if _, voted := g.voteRounds[0][id]; !voted {
			t.Errorf("%s chose and then dropped offline, and their vote was thrown away", id)
		}
	}
}

// A vote from somebody who has left the match is a different thing: it goes
// when they go.
func TestAVoteFromSomebodyWhoLeftIsDropped(t *testing.T) {
	g := newGame(t, 5)
	now := toVoting(t, g)
	c := citizens(g)
	must(t, g.Vote(c[0], g.impostor, now))
	must(t, g.Vote(c[1], g.impostor, now))
	must(t, g.Leave(c[0], now))
	g.Tick(now.Add(20 * time.Second))
	if len(g.voteRounds[0]) != 1 {
		t.Fatalf("counted %v, want only the vote of somebody still in the match", g.voteRounds[0])
	}
}

func TestCitizenLeavingLosesAndGameContinuesWithThree(t *testing.T) {
	g := newGame(t, 4)
	now := toVoting(t, g)
	c := citizens(g)
	must(t, g.Vote(c[1], c[0], now))
	must(t, g.Leave(c[0], now))
	wantPhase(t, g, PhaseVoting)
	if slices.Contains(g.candidates, c[0]) || len(g.votes) != 0 {
		t.Fatal("a player who left is no longer a candidate and their votes are dropped")
	}
	voteAllFor(t, g, citizens(g)[1], now)
	g.Tick(now.Add(20 * time.Second))
	if g.result.Outcomes[c[0]] != OutcomeLoss {
		t.Fatal("leaving mid-game is a loss")
	}
}

// Citizens walking out until one is left is the impostor winning, not a match
// that ran out of people. Parity does not care how the citizens went.
func TestCitizensWalkingOutToParityIsAnImpostorWin(t *testing.T) {
	g := newGame(t, 4)
	confirmAll(t, g)
	c := citizens(g)
	must(t, g.Leave(c[0], t0))
	wantPhase(t, g, PhaseHints)
	must(t, g.Leave(c[1], t0))
	wantResult(t, g, TeamImpostor, ReasonImpostorParity)
	for id, o := range g.result.Outcomes {
		want := OutcomeLoss
		if id == g.impostor {
			want = OutcomeWin
		}
		if o != want {
			t.Fatalf("%s outcome = %s, want %s", id, o, want)
		}
	}
}

func TestImpostorLeavingLoses(t *testing.T) {
	g := newGame(t, 4)
	confirmAll(t, g)
	must(t, g.Leave(g.impostor, t0))
	wantResult(t, g, TeamCitizens, ReasonImpostorGone)
	if g.result.Outcomes[g.impostor] != OutcomeLoss {
		t.Fatal("impostor who leaves loses")
	}
}

func TestLeavingResultScreenIsNotAbandonment(t *testing.T) {
	g := newGame(t, 4)
	now := citizensWin(t, g, toVoting(t, g))
	c := citizens(g)[0]
	before := g.result.Outcomes[c]
	must(t, g.Leave(c, now.Add(time.Minute)))
	if g.result.Outcomes[c] != before || g.players[c].status != StatusActive {
		t.Fatal("leaving after the end must not change the outcome")
	}
}

func TestStaleCommandsCannotRewindPhase(t *testing.T) {
	g := newGame(t, 4)
	now := toVoting(t, g)
	version := g.version
	wantErr(t, g.ConfirmRole(g.order[0], now), ErrWrongPhase)
	wantErr(t, g.SubmitHint(g.order[0], "again", now), ErrWrongPhase)
	wantPhase(t, g, PhaseVoting)
	if g.version != version {
		t.Fatal("rejected commands must not change the state version")
	}
}

func wantResult(t *testing.T, g *Game, winner Team, reason EndReason) {
	t.Helper()
	wantPhase(t, g, PhaseEnded)
	if g.result.Winner != winner || g.result.Reason != reason {
		t.Fatalf("result = %s/%s, want %s/%s", g.result.Winner, g.result.Reason, winner, reason)
	}
	if !g.Deadline().IsZero() {
		t.Fatal("ended game has no timer")
	}
}

func sameSet(a, b []string) bool {
	a, b = slices.Clone(a), slices.Clone(b)
	slices.Sort(a)
	slices.Sort(b)
	return slices.Equal(a, b)
}

// The runoff shows how the tie happened, but only for the players in it.
// Counting every target would tell the table how the group voted on someone
// who is not a candidate, which docs/protocol.md reveals only in result.
func TestRunoffPreviousVotesHideNonCandidates(t *testing.T) {
	g := newGame(t, 6)
	now := toVoting(t, g)
	c := citizens(g) // five citizens

	// c[1] and the impostor tie on two; c[0] draws one and misses the runoff.
	must(t, g.Vote(c[0], c[1], now))
	must(t, g.Vote(c[2], c[1], now))
	must(t, g.Vote(c[1], g.impostor, now))
	must(t, g.Vote(c[3], g.impostor, now))
	must(t, g.Vote(c[4], c[0], now))

	g.Tick(now.Add(20 * time.Second))
	wantPhase(t, g, PhaseRunoffVoting)
	if want := []string{c[1], g.impostor}; !sameSet(g.candidates, want) {
		t.Fatalf("runoff candidates = %v, want %v", g.candidates, want)
	}

	v, err := g.View(c[0])
	if err != nil {
		t.Fatal(err)
	}
	if v.PreviousVotes[c[1]] != 2 || v.PreviousVotes[g.impostor] != 2 {
		t.Fatalf("previous votes = %v, want two each for the tied players", v.PreviousVotes)
	}
	if _, leaked := v.PreviousVotes[c[0]]; leaked {
		t.Fatalf("previous votes leak a non-candidate's count: %v", v.PreviousVotes)
	}
	if len(v.PreviousVotes) != 2 {
		t.Fatalf("previous votes = %v, want only the two candidates", v.PreviousVotes)
	}
}

// The last hint does not open the vote: the table gets a moment on the
// finished board first (screen "עוברים להצבעה").
func TestLastHintHoldsTheBoardBeforeVoting(t *testing.T) {
	g := newGame(t, 4)
	confirmAll(t, g)
	now := t0
	for i, id := range g.order {
		now = now.Add(time.Second)
		must(t, g.SubmitHint(id, "hint"+string(rune('a'+i)), now))
		if g.phase == PhaseHintBreak {
			now = now.Add(3 * time.Second)
			g.Tick(now)
		}
	}

	// The last hint is held like the rest, and then the pre-vote screen opens.
	wantPhase(t, g, PhasePreVoting)
	if want := now.Add(5 * time.Second); !g.Deadline().Equal(want) {
		t.Fatalf("pre-voting deadline = %v, want %v", g.Deadline(), want)
	}
	// Every hint is on the board, and nobody can vote yet.
	v, _ := g.View(g.order[0])
	if len(v.Hints) != 4 || len(v.Candidates) != 0 {
		t.Fatalf("view = %d hints, %d candidates", len(v.Hints), len(v.Candidates))
	}
	wantErr(t, g.Vote(g.order[0], g.order[1], now), ErrWrongPhase)

	g.Tick(now.Add(4 * time.Second))
	wantPhase(t, g, PhasePreVoting)
	g.Tick(now.Add(5 * time.Second))
	wantPhase(t, g, PhaseVoting)
	must(t, g.Vote(g.order[0], g.order[1], now.Add(5*time.Second)))
}

// A hint is held so the table can read it before the next turn takes the
// screen, and the clock for that next turn only starts afterwards.
func TestHintIsHeldBeforeTheNextTurn(t *testing.T) {
	g := newGame(t, 4)
	confirmAll(t, g)
	must(t, g.SubmitHint(g.order[0], "גדול", t0))

	wantPhase(t, g, PhaseHintBreak)
	if want := t0.Add(3 * time.Second); !g.Deadline().Equal(want) {
		t.Fatalf("hold deadline = %v, want %v", g.Deadline(), want)
	}
	// The hint is on the board, and nobody is on the clock.
	v, _ := g.View(g.order[1])
	if len(v.Hints) != 1 || v.Hints[0].Text != "גדול" || v.CurrentTurn != "" {
		t.Fatalf("view during the hold = %+v", v)
	}
	wantErr(t, g.SubmitHint(g.order[1], "מוקדם", t0), ErrWrongPhase)

	// The next player's full turn begins only when the hold ends.
	g.Tick(t0.Add(3 * time.Second))
	wantPhase(t, g, PhaseHints)
	if want := t0.Add(63 * time.Second); !g.Deadline().Equal(want) {
		t.Fatalf("next turn deadline = %v, want %v", g.Deadline(), want)
	}
	must(t, g.SubmitHint(g.order[1], "אפור", t0.Add(4*time.Second)))
}

// A turn nobody wrote in has nothing to read, so it is not held.
func TestSkippedTurnIsNotHeld(t *testing.T) {
	g := newGame(t, 4)
	confirmAll(t, g)
	g.Tick(t0.Add(60 * time.Second)) // the first turn runs out
	wantPhase(t, g, PhaseHints)
	if g.order[g.turn] != g.order[1] {
		t.Fatal("a skipped turn should move straight on")
	}
}

// Reacting to "the last hint" right after a skipped turn lands on the last
// hint somebody gave, instead of failing for the whole table.
func TestReactionAfterASkippedTurnGoesToTheLastRealHint(t *testing.T) {
	g := newGame(t, 4)
	confirmAll(t, g)
	must(t, g.SubmitHint(g.order[0], "חדק", t0))
	g.Tick(t0.Add(6 * time.Second))  // the second turn starts
	g.Tick(t0.Add(67 * time.Second)) // and runs out
	if !g.hints[1].Missing {
		t.Fatalf("hint 1 = %+v, want missing", g.hints[1])
	}
	must(t, g.React(g.order[2], 1, "suspicious", t0.Add(68*time.Second)))
	if n := g.hints[0].Reactions["suspicious"]; n != 1 {
		t.Fatalf("reactions on the last real hint = %d, want 1", n)
	}
}

// Leaving and coming back during your own turn cannot buy time: the turn's
// clock keeps running while you are away and resumes where it was.
func TestReconnectCyclingCannotExtendTheTurn(t *testing.T) {
	g := newGame(t, 4)
	confirmAll(t, g)
	p := g.order[0]
	turnEnds := g.turnDeadline
	now := t0
	for range 10 {
		now = now.Add(5 * time.Second)
		must(t, g.Disconnect(p, now))
		now = now.Add(time.Second)
		must(t, g.Reconnect(p, now))
		if g.phase == PhaseHints && g.order[g.turn] == p && g.Deadline().After(turnEnds) {
			t.Fatalf("turn deadline moved to %v, past its own end %v", g.Deadline(), turnEnds)
		}
	}
	g.Tick(turnEnds)
	if g.order[g.turn] == p || !g.hints[0].Missing {
		t.Fatal("the turn outlived its 60 s")
	}
}

// Once the impostor is caught, only the guess decides: a citizen walking out
// during it does not hand the impostor a parity win.
func TestCitizenLeavingDuringTheGuessDoesNotDecideTheMatch(t *testing.T) {
	g := newGame(t, 4)
	now := toVoting(t, g)
	voteAllFor(t, g, g.impostor, now)
	g.Tick(now.Add(DefaultConfig().VoteDuration))
	wantPhase(t, g, PhaseImpostorGuess)
	must(t, g.Leave(citizens(g)[0], now.Add(21*time.Second)))
	wantPhase(t, g, PhaseImpostorGuess)
	must(t, g.SubmitGuess(g.impostor, "לא נכון", now.Add(22*time.Second)))
	wantResult(t, g, TeamCitizens, ReasonImpostorGuessWrong)
}

// Symbols alone are no hint, and invisible characters can neither smuggle in
// a second word nor split the secret word apart.
func TestHintTextIsCleanedBeforeTheRules(t *testing.T) {
	g := newGame(t, 4)
	confirmAll(t, g)
	var citizen string
	for _, id := range g.order {
		if id != g.impostor {
			citizen = id
			break
		}
	}
	for g.order[g.turn] != citizen {
		must(t, g.SubmitHint(g.order[g.turn], fmt.Sprintf("רמז%d", g.turn), t0))
		g.Tick(t0.Add(10 * time.Second))
	}
	now := t0.Add(10 * time.Second)
	wantErr(t, g.SubmitHint(citizen, "🙂!!", now), ErrHintEmpty)
	wantErr(t, g.SubmitHint(citizen, "שתי⠀מילים", now), ErrHintNotOneWord)
	wantErr(t, g.SubmitHint(citizen, "פי\u200bל", now), ErrHintContainsSecret)
}
