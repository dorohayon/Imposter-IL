package api

import (
	"math"
	"slices"
	"testing"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/content"
	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

// The wiring, which the content package cannot see: which pool a bot reaches
// for is decided by whether the game handed it a secret word, and the game
// hands one only to citizens.
func TestBotsReachForThePoolTheirRoleAllows(t *testing.T) {
	const word = "פיצה"
	citizen := game.View{Category: "אוכל", SecretWord: word}
	if got := botHintPool(citizen); !slices.Equal(got, content.CitizenHints(word)) {
		t.Errorf("a citizen bot got %v, want the word's own pool", got)
	}

	// An impostor's View carries no secret word, so the same call cannot
	// return the word's pool even though the process is holding the word.
	impostor := game.View{Category: "אוכל"}
	got := botHintPool(impostor)
	for _, hint := range content.CitizenHints(word) {
		if slices.Contains(got, hint) && !slices.Contains(content.ImpostorHints("אוכל", nil), hint) {
			t.Errorf("an impostor bot was offered %q, which only the word's pool has", hint)
		}
	}
	if !slices.Equal(got, content.ImpostorHints("אוכל", nil)) {
		t.Errorf("an impostor bot with an empty board got %v, want the category pool", got)
	}

	// With hints on the board it may narrow, but only using the board.
	board := game.View{Category: "אוכל", Hints: []game.Hint{
		{PlayerID: "p1", Text: "מתוק"},
		{PlayerID: "p2", Text: "קר", Missing: true},
	}}
	if got := botHintPool(board); slices.Contains(got, "מתוק") {
		t.Error("an impostor bot was offered a hint already on the board")
	}
	if got := botHintPool(game.View{Category: "לא קיים"}); !slices.Equal(got, stagingBotHints) {
		t.Errorf("an unknown category fell through to %v, want the last resort", got)
	}
}

// The invariant, checked where it is spent rather than where it is computed:
// the same board must produce the same votes whatever the round is underneath.
func TestVotingIsIndependentOfTheSecretWordAndTheRoles(t *testing.T) {
	srv := NewServer(time.Now, content.Policy(), content.Pick)
	pool := content.CitizenHints("פיצה")
	hints := []game.Hint{
		{PlayerID: "p1", Text: pool[0]},
		{PlayerID: "p2", Text: pool[1]},
		{PlayerID: "p3", Text: "מסדרון"},
	}
	candidates := []string{"p1", "p2", "p3"}

	tally := func(view game.View) map[string]float64 {
		counts := map[string]int{}
		const rounds = 40000
		for i := 0; i < rounds; i++ {
			counts[srv.botVote(view, candidates)]++
		}
		out := map[string]float64{}
		for id, n := range counts {
			out[id] = float64(n) / rounds
		}
		return out
	}

	// A citizen bot holding the word, and an impostor bot holding none. Same
	// board, so the same votes — the reading has no parameter for either.
	citizen := tally(game.View{Category: "אוכל", SecretWord: "פיצה", Hints: hints, Role: game.RoleCitizen})
	impostor := tally(game.View{Category: "אוכל", Hints: hints, Role: game.RoleImpostor})
	other := tally(game.View{Category: "אוכל", SecretWord: "סושי", Hints: hints, Role: game.RoleCitizen})
	for id := range citizen {
		for name, got := range map[string]float64{"impostor": impostor[id], "another word": other[id]} {
			if math.Abs(got-citizen[id]) > 0.02 {
				t.Errorf("%s voted for %q %.1f%% against %.1f%%: the round leaked into the vote",
					name, id, 100*got, 100*citizen[id])
			}
		}
	}

	// And the person writing a word nobody curated is not thereby singled out.
	if share := citizen["p3"]; share < 0.28 || share > 0.39 {
		t.Errorf("the unheard-of word took %.1f%% of the votes, want about a third", 100*share)
	}
}
