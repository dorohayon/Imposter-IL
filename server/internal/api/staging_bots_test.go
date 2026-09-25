package api

import (
	"math"
	"slices"
	"testing"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/content"
	"github.com/dorohayon/Imposter-IL/server/internal/game"
	"github.com/dorohayon/Imposter-IL/server/internal/matchmaking"
)

func TestStagingBotsDesired(t *testing.T) {
	if stagingBotsDesired(5, 1) != 5 {
		t.Fatal("one human should get the full staging roster")
	}
	if stagingBotsDesired(5, 2) != 2 {
		t.Fatal("two humans should yield down to two bots")
	}
	if stagingBotsDesired(5, 4) != 0 {
		t.Fatal("four humans need no bots")
	}
	if stagingBotsDesired(0, 1) != 0 {
		t.Fatal("disabled staging stays off")
	}
	if stagingBotsDesired(5, 1) > matchmaking.MaxPlayers-1 {
		t.Fatal("staging bots must leave room for the human")
	}
}

// The wiring, which the content package cannot see: which pool a bot reaches
// for is decided by whether the game handed it a secret word, and the game
// hands one only to citizens.
func TestBotsReachForThePoolTheirRoleAllows(t *testing.T) {
	const (
		category = "אוכל ושתייה"
		word     = "פיצה"
	)
	citizen := game.View{Category: category, SecretWord: word}
	own := content.CitizenHints(category, word)
	got := botHintPool(citizen)
	// The word's own hints come first; the broad pool trails them, because a
	// match runs several rounds and six hints run out.
	if len(got) <= len(own) || !slices.Equal(got[:len(own)], own) {
		t.Errorf("a citizen bot got %v, want the word's own pool first", got)
	}

	// An impostor's View carries no secret word, so the same call cannot
	// return the word's pool even though the process is holding the word.
	impostor := game.View{Category: category}
	got = botHintPool(impostor)
	for _, hint := range content.CitizenHints(category, word) {
		if slices.Contains(got, hint) && !slices.Contains(content.ImpostorHints(category, nil), hint) {
			t.Errorf("an impostor bot was offered %q, which only the word's pool has", hint)
		}
	}
	if !slices.Equal(got, content.ImpostorHints(category, nil)) {
		t.Errorf("an impostor bot with an empty board got %v, want the category pool", got)
	}

	// With hints on the board it may narrow, but only using the board.
	board := game.View{Category: category, Hints: []game.Hint{
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
	pool := content.CitizenHints("אוכל ושתייה", "פיצה")
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
	citizen := tally(game.View{Category: "אוכל ושתייה", SecretWord: "פיצה", Hints: hints, Role: game.RoleCitizen})
	impostor := tally(game.View{Category: category, Hints: hints, Role: game.RoleImpostor})
	other := tally(game.View{Category: "אוכל ושתייה", SecretWord: "סושי", Hints: hints, Role: game.RoleCitizen})
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

// A bot's name goes in front of a player, so it obeys the same rules a
// player's nickname does, and its avatar has to be one that exists.
func TestBotNamesAreNamesAPlayerCouldHave(t *testing.T) {
	avatars := map[string]bool{}
	for _, list := range stagingBotAvatars {
		for _, a := range list {
			avatars[a] = true
		}
	}
	for gender, names := range stagingBotNames {
		if len(names) < 8 {
			t.Errorf("%s has only %d names: a table of four would repeat too often", gender, len(names))
		}
		for _, name := range names {
			nickname := "בוט " + name
			if _, ok := validNickname(nickname); !ok {
				t.Errorf("%q is not a nickname the server would accept", nickname)
			}
			if content.Blocked(nickname) {
				t.Errorf("%q is on the blocked list", nickname)
			}
		}
	}

	// A full table's worth, drawn over and over: never a repeated name or a
	// repeated avatar, and never an avatar that does not exist.
	srv := NewServer(time.Now, content.Policy(), content.Pick)
	for round := 0; round < 2000; round++ {
		var table []*session
		for seat := 0; seat < 3; seat++ {
			nickname, avatar := srv.botProfile(table)
			if !avatars[avatar] {
				t.Fatalf("%q is not one of the avatars", avatar)
			}
			for _, other := range table {
				if other.nickname == nickname {
					t.Fatalf("two bots called %q at one table", nickname)
				}
				if other.avatarID == avatar {
					t.Fatalf("two bots wearing %q at one table", avatar)
				}
			}
			table = append(table, &session{nickname: nickname, avatarID: avatar})
		}
	}
}

// The name and the face agree, which is the point of keeping two lists.
func TestABotsAvatarMatchesItsName(t *testing.T) {
	srv := NewServer(time.Now, content.Policy(), content.Pick)
	gender := map[string]string{}
	for g, names := range stagingBotNames {
		for _, n := range names {
			gender["בוט "+n] = g
		}
	}
	for i := 0; i < 3000; i++ {
		nickname, avatar := srv.botProfile(nil)
		want := gender[nickname]
		if !slices.Contains(stagingBotAvatars[want], avatar) {
			t.Fatalf("%q was given %q, which is not a %s avatar", nickname, avatar, want)
		}
	}
}
