package api

import (
	"slices"
	"testing"

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
