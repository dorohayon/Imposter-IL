package api

import (
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

// A bot must not be able to find the person at the table by noticing that
// their words are not in its own dataset. This is that property measured where
// it matters — in the votes themselves, not in the score that feeds them.
func TestBotsDoNotHuntTheHumanAtTheTable(t *testing.T) {
	srv := NewServer(time.Now, content.Policy(), content.Pick)
	const word = "פיצה"
	pool := content.CitizenHints(word)

	// Three suspects. Two bots wrote hints from the word's own pool; the person
	// wrote their own word, which is in no pool anywhere.
	view := game.View{
		Category:   "אוכל",
		SecretWord: word,
		Hints: []game.Hint{
			{PlayerID: "bot1", Text: pool[0]},
			{PlayerID: "bot2", Text: pool[1]},
			{PlayerID: "human", Text: "מילהשלאדם"},
		},
	}
	candidates := []string{"bot1", "bot2", "human"}

	votes := map[string]int{}
	const rounds = 30000
	for i := 0; i < rounds; i++ {
		votes[srv.botVote(view, candidates)]++
	}
	// Even odds are 1 in 3. The person may not be singled out beyond the noise
	// of thirty thousand rounds.
	share := float64(votes["human"]) / rounds
	if share < 0.31 || share > 0.36 {
		t.Errorf("the person took %.1f%% of the votes, want about 33%%: %v", 100*share, votes)
	}

	// And the measure still has an opinion when it can form one: swap the
	// person's hint for one that belongs to soup rather than pizza.
	view.Hints[2].Text = "מרפאה"
	votes = map[string]int{}
	for i := 0; i < rounds; i++ {
		votes[srv.botVote(view, candidates)]++
	}
	if got := float64(votes["human"]) / rounds; got < 0.4 {
		t.Errorf("a hint from the wrong cluster drew only %.1f%% of the votes", 100*got)
	}

	// Nobody votes for themselves, which the caller guarantees by leaving the
	// voter out of the candidates; make sure botVote respects the list it gets.
	for i := 0; i < 200; i++ {
		if got := srv.botVote(view, []string{"bot1"}); got != "bot1" {
			t.Fatalf("botVote returned %q for a single candidate", got)
		}
	}
}
