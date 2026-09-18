package game

import (
	"testing"
	"time"
)

// playRound walks a round from wherever the hints phase is to the vote opening.
func playRound(t *testing.T, g *Game, now time.Time) time.Time {
	t.Helper()
	for g.phase == PhaseHints || g.phase == PhaseHintBreak {
		if g.phase == PhaseHintBreak {
			now = now.Add(DefaultConfig().HintBreakDuration)
			g.Tick(now)
			continue
		}
		now = now.Add(time.Second)
		must(t, g.SubmitHint(g.order[g.turn], uniqueHint(g), now))
	}
	wantPhase(t, g, PhasePreVoting)
	now = now.Add(DefaultConfig().PreVotingDuration)
	g.Tick(now)
	wantPhase(t, g, PhaseVoting)
	return now
}

// uniqueHint is a word the match has not heard, judged by the engine's own
// duplicate rule rather than by string equality — walking the alphabet lands
// on ך and then כ, which normalisation folds together.
func uniqueHint(g *Game) string {
	for i := 0; ; i++ {
		word := "רמז" + string(rune('א'+i))
		used := false
		for _, h := range g.hints {
			if !h.Missing && sameHint(word, h.Text) {
				used = true
			}
		}
		if !used {
			return word
		}
	}
}

// voteOut sends every active voter at one target and closes the vote.
func voteOut(t *testing.T, g *Game, target string, now time.Time) time.Time {
	t.Helper()
	for _, id := range g.activeIDs() {
		if id != target {
			must(t, g.Vote(id, target, now))
		}
	}
	now = now.Add(DefaultConfig().VoteDuration)
	g.Tick(now)
	return now
}

// Citizens voted out one after another, until the impostor is the last one
// standing beside a single citizen and the match is already decided.
func TestConsecutiveEliminationsEndInParity(t *testing.T) {
	g := newGame(t, 5) // four citizens, one impostor
	confirmAll(t, g)
	now := playRound(t, g, t0)

	out := citizens(g)[0]
	now = voteOut(t, g, out, now)
	if g.round != 2 || g.players[out].status != StatusEliminated {
		t.Fatalf("round %d, %s is %q", g.round, out, g.players[out].status)
	}

	second := citizens(g)[0]
	now = playRound(t, g, now)
	now = voteOut(t, g, second, now)
	if g.round != 3 || g.players[second].status != StatusEliminated {
		t.Fatalf("round %d, %s is %q", g.round, second, g.players[second].status)
	}
	if c, i := g.citizensAndImpostors(); c != 2 || i != 1 {
		t.Fatalf("two citizens and an impostor expected, got %d and %d", c, i)
	}

	// The third costs the citizens the match: one of them against the impostor
	// is nobody left to outvote him.
	third := citizens(g)[0]
	now = playRound(t, g, now)
	voteOut(t, g, third, now)
	wantResult(t, g, TeamImpostor, ReasonImpostorParity)

	// Everyone voted out is still on the citizens' side of the result.
	for _, id := range []string{out, second, third} {
		if got := g.result.Outcomes[id]; got != OutcomeLoss {
			t.Errorf("%s got %q: a voted-out citizen loses with the citizens", id, got)
		}
	}
	if got := g.result.Outcomes[g.impostor]; got != OutcomeWin {
		t.Errorf("the impostor got %q", got)
	}
}

// The other ending: the table catches him, and the guess decides it.
func TestCatchingTheImpostorGoesToTheGuess(t *testing.T) {
	for _, tc := range []struct {
		name   string
		guess  string
		winner Team
		reason EndReason
	}{
		{"right", secret, TeamImpostor, ReasonImpostorGuessedWord},
		{"wrong", "לאיודע", TeamCitizens, ReasonImpostorGuessWrong},
	} {
		t.Run(tc.name, func(t *testing.T) {
			g := newGame(t, 5)
			confirmAll(t, g)
			now := playRound(t, g, t0)
			// Vote out a citizen first, so the guess happens in a later round
			// with a spectator watching.
			out := citizens(g)[0]
			now = voteOut(t, g, out, now)
			now = playRound(t, g, now)
			now = voteOut(t, g, g.impostor, now)
			wantPhase(t, g, PhaseImpostorGuess)

			must(t, g.SubmitGuess(g.impostor, tc.guess, now))
			wantResult(t, g, tc.winner, tc.reason)
			// The citizen voted out in round one shares the citizens' result.
			want := OutcomeWin
			if tc.winner == TeamImpostor {
				want = OutcomeLoss
			}
			if got := g.result.Outcomes[out]; got != want {
				t.Errorf("the eliminated citizen got %q, want %q", got, want)
			}
		})
	}
}

// A guess that never comes is a loss for the impostor, in a later round too.
func TestTheGuessCanTimeOutInALaterRound(t *testing.T) {
	g := newGame(t, 5)
	confirmAll(t, g)
	now := playRound(t, g, t0)
	now = voteOut(t, g, citizens(g)[0], now)
	now = playRound(t, g, now)
	now = voteOut(t, g, g.impostor, now)
	g.Tick(now.Add(DefaultConfig().GuessDuration))
	wantResult(t, g, TeamCitizens, ReasonImpostorGuessTimeout)
}

// What a player voted out may and may not do.
func TestASpectatorWatchesAndReactsAndNothingElse(t *testing.T) {
	g := newGame(t, 5)
	confirmAll(t, g)
	now := playRound(t, g, t0)
	out := citizens(g)[0]
	now = voteOut(t, g, out, now)

	// No turn, no hint, no vote.
	wantErr(t, g.SubmitHint(out, "רמזחדש", now), ErrPlayerNotActive)
	if g.order[g.turn] == out {
		t.Fatal("a spectator was given a turn")
	}
	now = playRound(t, g, now)
	wantErr(t, g.Vote(out, g.impostor, now), ErrPlayerNotActive)
	if v, _ := g.View(out); len(v.Candidates) > 0 {
		for _, c := range v.Candidates {
			if c == out {
				t.Fatal("a spectator is still a candidate")
			}
		}
	}

	// Reacting is what they keep.
	must(t, g.React(out, 0, "suspicious", now))
	if v, _ := g.View(out); v.Hints[0].Reactions["suspicious"] != 1 {
		t.Fatal("a spectator's reaction was not counted")
	}

	// And they can come and go without it costing them the match.
	must(t, g.Disconnect(out, now))
	if g.players[out].disconnects != 0 {
		t.Errorf("a spectator's disconnect was counted: %d", g.players[out].disconnects)
	}
	must(t, g.Reconnect(out, now))
	if g.players[out].status != StatusEliminated {
		t.Fatalf("status after reconnecting = %q", g.players[out].status)
	}
}

// A spectator who walks out is abandoning the match, and that is on them.
func TestASpectatorWhoLeavesStillLoses(t *testing.T) {
	g := newGame(t, 5)
	confirmAll(t, g)
	now := playRound(t, g, t0)
	out := citizens(g)[0]
	now = voteOut(t, g, out, now)
	must(t, g.Leave(out, now))
	if g.players[out].status != StatusLeft {
		t.Fatalf("status = %q, want left", g.players[out].status)
	}
	now = playRound(t, g, now)
	now = voteOut(t, g, g.impostor, now)
	must(t, g.SubmitGuess(g.impostor, "לאיודע", now))
	if got := g.result.Outcomes[out]; got != OutcomeLoss {
		t.Errorf("a spectator who walked out got %q", got)
	}
}

// What a reconnecting player is told in a later round.
func TestAViewCarriesTheRoundAndTheStatus(t *testing.T) {
	g := newGame(t, 5)
	confirmAll(t, g)
	now := playRound(t, g, t0)
	out := citizens(g)[0]
	voteOut(t, g, out, now)

	for _, id := range g.order {
		v, err := g.View(id)
		if err != nil {
			t.Fatal(err)
		}
		if v.Round != 2 {
			t.Errorf("%s sees round %d, want 2", id, v.Round)
		}
		var status PlayerStatus
		for _, pv := range v.Players {
			if pv.ID == out {
				status = pv.Status
			}
		}
		if status != StatusEliminated {
			t.Errorf("%s sees %s as %q", id, out, status)
		}
		// The board they come back to still holds the first round.
		if len(v.Hints) != 5 || v.Hints[0].Round != 1 {
			t.Errorf("%s sees %d hints, first from round %d", id, len(v.Hints), v.Hints[0].Round)
		}
	}
}

// A hint may not repeat one from an earlier round.
func TestTheDuplicateRuleSpansTheWholeMatch(t *testing.T) {
	g := newGame(t, 5)
	confirmAll(t, g)
	now := playRound(t, g, t0)
	first := g.hints[0].Text
	now = voteOut(t, g, citizens(g)[0], now)
	wantPhase(t, g, PhaseHints)
	wantErr(t, g.SubmitHint(g.order[g.turn], first, now), ErrHintDuplicate)
	// And the prefixed form of it, the same as inside one round.
	wantErr(t, g.SubmitHint(g.order[g.turn], "ה"+first, now), ErrHintDuplicate)
}

// Rule ten: a stale timer or a repeated command must not move the match twice.
func TestStaleTimersAndRepeatedCommandsChangeNothing(t *testing.T) {
	g := newGame(t, 5)
	confirmAll(t, g)
	now := playRound(t, g, t0)
	now = voteOut(t, g, citizens(g)[0], now)
	round, version := g.round, g.version

	// Every deadline that has already passed, applied again.
	for i := 0; i < 5; i++ {
		g.Tick(now)
	}
	if g.round != round || g.version != version {
		t.Fatalf("replaying passed deadlines moved the match: round %d->%d, version %d->%d",
			round, g.round, version, g.version)
	}

	// The match ends once, however many ways it is told to.
	now = playRound(t, g, now)
	now = voteOut(t, g, g.impostor, now)
	must(t, g.SubmitGuess(g.impostor, secret, now))
	wantResult(t, g, TeamImpostor, ReasonImpostorGuessedWord)
	ended := *g.result

	wantErr(t, g.SubmitGuess(g.impostor, "לאיודע", now), ErrWrongPhase)
	g.Tick(now.Add(time.Hour))
	if g.result.Winner != ended.Winner || g.result.Reason != ended.Reason {
		t.Fatalf("the result changed after the end: %+v", g.result)
	}
	if !g.Deadline().IsZero() {
		t.Fatalf("a finished match still has a deadline at %v", g.Deadline())
	}
}

// A table that stops voting is a table that has gone home, and rounds run
// until somebody wins, so something has to call it.
func TestTwoSilentVotesCallTheMatchOff(t *testing.T) {
	g := newGame(t, 5)
	confirmAll(t, g)
	now := playRound(t, g, t0)

	// Nobody votes. One round like that is a table that could not decide.
	now = now.Add(DefaultConfig().VoteDuration)
	g.Tick(now)
	if g.result != nil {
		t.Fatalf("one silent vote ended the match: %+v", g.result)
	}
	if g.round != 2 {
		t.Fatalf("round = %d, want 2", g.round)
	}

	// Twice is a table that is not there.
	now = playRound(t, g, now)
	now = now.Add(DefaultConfig().VoteDuration)
	g.Tick(now)
	wantResult(t, g, TeamNone, ReasonAbandoned)

	// It counts for nobody: not a win, not a loss, nothing to record.
	for id, outcome := range g.result.Outcomes {
		if outcome != OutcomeNone {
			t.Errorf("%s got %q from a match that was called off", id, outcome)
		}
	}
}

// One vote is enough to say the table is still there.
func TestASingleVoteResetsTheSilence(t *testing.T) {
	g := newGame(t, 5)
	confirmAll(t, g)
	now := playRound(t, g, t0)

	now = now.Add(DefaultConfig().VoteDuration)
	g.Tick(now) // silent once
	now = playRound(t, g, now)

	// One player votes; nobody is eliminated, because one vote for one target
	// still picks somebody — so pick a citizen and let the round go on.
	voter := citizens(g)[0]
	target := citizens(g)[1]
	must(t, g.Vote(voter, target, now))
	now = now.Add(DefaultConfig().VoteDuration)
	g.Tick(now)
	if g.result != nil {
		t.Fatalf("a round with a vote in it ended the match: %+v", g.result)
	}
	if g.silentVotes != 0 {
		t.Fatalf("silentVotes = %d after a vote was cast", g.silentVotes)
	}

	// And now silence has to start over: one more is not enough.
	now = playRound(t, g, now)
	now = now.Add(DefaultConfig().VoteDuration)
	g.Tick(now)
	if g.result != nil {
		t.Fatalf("the counter did not reset: %+v", g.result)
	}
}

// People who voted and disagreed are still playing.
func TestATieIsNotSilence(t *testing.T) {
	g := newGame(t, 5)
	confirmAll(t, g)
	now := playRound(t, g, t0)

	// Two citizens each pick a different target: a tie, with votes in it.
	c := citizens(g)
	must(t, g.Vote(c[0], c[1], now))
	must(t, g.Vote(c[1], g.impostor, now))
	now = now.Add(DefaultConfig().VoteDuration)
	g.Tick(now)
	wantPhase(t, g, PhaseRunoffVoting)
	if g.silentVotes != 0 {
		t.Fatalf("a tie counted as silence: silentVotes = %d", g.silentVotes)
	}

	// The runoff ties too, so nobody is eliminated and the match goes on.
	must(t, g.Vote(c[0], c[1], now))
	must(t, g.Vote(c[2], g.impostor, now))
	now = now.Add(DefaultConfig().RunoffVoteDuration)
	g.Tick(now)
	if g.result != nil {
		t.Fatalf("two ties ended the match: %+v", g.result)
	}
	if g.silentVotes != 0 {
		t.Fatalf("a second tie counted as silence: silentVotes = %d", g.silentVotes)
	}
	if g.round != 2 {
		t.Fatalf("round = %d, want 2", g.round)
	}

	// Ties are not silence, so it still takes two silent votes to call it off.
	now = playRound(t, g, now)
	now = now.Add(DefaultConfig().VoteDuration)
	g.Tick(now)
	if g.result != nil {
		t.Fatalf("one silent vote after two ties ended the match: %+v", g.result)
	}
	now = playRound(t, g, now)
	now = now.Add(DefaultConfig().VoteDuration)
	g.Tick(now)
	wantResult(t, g, TeamNone, ReasonAbandoned)
}

// A runoff nobody turns up for counts, because a runoff is a voting phase.
func TestASilentRunoffCounts(t *testing.T) {
	g := newGame(t, 5)
	confirmAll(t, g)
	now := playRound(t, g, t0)
	c := citizens(g)
	must(t, g.Vote(c[0], c[1], now))
	must(t, g.Vote(c[1], g.impostor, now))
	now = now.Add(DefaultConfig().VoteDuration)
	g.Tick(now)
	wantPhase(t, g, PhaseRunoffVoting)

	// Nobody votes in the runoff: one silent phase, and the match goes on.
	now = now.Add(DefaultConfig().RunoffVoteDuration)
	g.Tick(now)
	if g.result != nil {
		t.Fatalf("a silent runoff alone ended the match: %+v", g.result)
	}
	if g.silentVotes != 1 {
		t.Fatalf("silentVotes = %d after a silent runoff, want 1", g.silentVotes)
	}

	now = playRound(t, g, now)
	now = now.Add(DefaultConfig().VoteDuration)
	g.Tick(now)
	wantResult(t, g, TeamNone, ReasonAbandoned)
}
