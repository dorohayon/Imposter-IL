package content

import (
	"slices"
	"testing"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

// The dataset has to obey the rules a real turn obeys, or a curated hint is a
// bot that says nothing on its turn. docs/bot-hints.md states them; this is
// the same list, checked with the engine's own functions.
func TestCitizenHintsAreUsable(t *testing.T) {
	for _, c := range Categories {
		for _, word := range c.Words {
			hints := CitizenHints(word)
			for i, hint := range hints {
				if !UsableHint(hint, word) {
					t.Errorf("%s/%s: %q is not a hint the engine would take", c.Name, word, hint)
				}
				// Duplicates inside one pool, prefix forms included: the second
				// one would be refused, so it is a wasted hint.
				for _, other := range hints[i+1:] {
					if sameHint(hint, other) {
						t.Errorf("%s/%s: %q and %q are the same hint", c.Name, word, hint, other)
					}
				}
			}
		}
	}
}

// The impostor's hint is never checked against the secret word, so a fallback
// that is also a word in its own category lets an impostor bot say the answer
// out loud. תיק and שולחן both did this before the dataset existed.
func TestFallbackHintsAreNotTheAnswer(t *testing.T) {
	for _, c := range Categories {
		pool := tables.fallback[c.Name]
		if len(pool) < 10 || len(pool) > 16 {
			t.Errorf("%s: %d fallback hints, want 10 to 16", c.Name, len(pool))
		}
		for i, hint := range pool {
			if !UsableHint(hint, "") {
				t.Errorf("%s: %q is not a hint the engine would take", c.Name, hint)
			}
			for _, word := range c.Words {
				if sameHint(hint, word) || containsWord(hint, word) {
					t.Errorf("%s: fallback %q gives away the word %q", c.Name, hint, word)
				}
			}
			for _, other := range pool[i+1:] {
				if sameHint(hint, other) {
					t.Errorf("%s: %q and %q are the same fallback", c.Name, hint, other)
				}
			}
		}
	}
}

// The property the whole structure exists for: what the impostor may say is a
// function of the category and the board, and of nothing else. It cannot be
// asked about a secret word, and the engine never hands it one — an impostor's
// View carries no secret word at all.
func TestImpostorHintsCannotDependOnTheWord(t *testing.T) {
	if got := CitizenHints(""); got != nil {
		t.Errorf(`CitizenHints("") = %v, want nil: that is what an impostor's view holds`, got)
	}
	for _, c := range Categories {
		board := []string{"טעים", "חם"}
		want := ImpostorHints(c.Name, board)
		// Nothing about the round can change it, because nothing about the
		// round reaches it.
		for _, word := range c.Words {
			if got := ImpostorHints(c.Name, board); !slices.Equal(got, want) {
				t.Fatalf("%s: the candidate list moved while the word was %q", c.Name, word)
			}
		}
		for _, hint := range want {
			if slices.Contains(board, hint) {
				t.Errorf("%s: %q is already on the board", c.Name, hint)
			}
		}
	}
}

// With an empty board the impostor can only be broad, which is the corner a
// human impostor opening the round is in too.
func TestImpostorOpensWithTheCategory(t *testing.T) {
	for _, c := range Categories {
		got := ImpostorHints(c.Name, nil)
		if !slices.Equal(got, tables.fallback[c.Name]) {
			t.Errorf("%s: opening hints are not the category pool", c.Name)
		}
	}
	if got := ImpostorHints("לא קיים", nil); len(got) != 0 {
		t.Errorf("an unknown category offered %v", got)
	}
}

// Every word owes a pool, or its bots fall back to the category and the round
// reads like the one before it.
func TestEveryWordHasCitizenHints(t *testing.T) {
	missing, wrongSize := 0, 0
	for _, c := range Categories {
		for _, word := range c.Words {
			switch n := len(CitizenHints(word)); {
			case n == 0:
				missing++
			case n < 5 || n > 7:
				wrongSize++
				t.Errorf("%s/%s: %d hints, want 5 to 7", c.Name, word, n)
			}
		}
	}
	if missing > 0 {
		t.Errorf("%d words have no citizen hints (docs/bot-hints.md)", missing)
	}
	_ = wrongSize
}

// A key for a word that is not in the category means the word list moved and
// the dataset did not follow.
func TestDatasetFollowsTheWordList(t *testing.T) {
	known := map[string]bool{}
	for _, c := range Categories {
		for _, word := range c.Words {
			known[word] = true
		}
	}
	for word := range tables.citizen {
		if !known[word] {
			t.Errorf("%q has hints but is not a word in any category", word)
		}
	}
	for category := range tables.fallback {
		if !slices.ContainsFunc(Categories, func(c Category) bool { return c.Name == category }) {
			t.Errorf("%q has a fallback pool but is not a category", category)
		}
	}
}

// sameHint is the engine's duplicate rule, which the dataset has to respect.
func sameHint(a, b string) bool {
	x, y := game.NormalizeWord(a), game.NormalizeWord(b)
	return x == y || game.IsPrefixedForm(x, y) || game.IsPrefixedForm(y, x)
}

// The derivation, against a fixture rather than the shipped file, so the part
// that actually reasons is exercised whatever the dataset happens to hold.
//
// Three sweet things and two hot ones, overlapping the way a real category
// does. Note וניל, כף and כוס: each belongs to one word only, which is what
// makes them that word's signature.
const fixture = `{
  "version": 1,
  "categories": [
    {
      "id": "food", "name": "אוכל",
      "impostorFallbackHints": ["ארוחה", "מנה"],
      "citizenHints": {
        "גלידה": ["מתוק", "קר", "קיץ", "וניל"],
        "סורבה": ["מתוק", "קר", "קיץ", "פירות"],
        "מאפה":  ["מתוק", "חם", "תנור", "פירות"],
        "מרק":   ["חם", "כף", "חורף", "תנור"],
        "תה":    ["חם", "חורף", "כוס", "מתוק"]
      }
    }
  ]
}`

func TestTheBoardNarrowsTheImpostor(t *testing.T) {
	f := loadHintTables([]byte(fixture))

	// A hint belonging to one word is that word's signature. However well it
	// would score, the impostor must never be offered it — that is the line
	// between reading the board and knowing the answer.
	for _, signature := range []string{"וניל", "כף", "כוס"} {
		if slices.Contains(f.shared["אוכל"], signature) {
			t.Errorf("%q belongs to one word and still reached the impostor", signature)
		}
	}

	// Nothing on the board: only the broad pool, which is the corner a human
	// impostor opening the round is in too.
	if got := f.impostorHints("אוכל", nil); !slices.Equal(got, []string{"ארוחה", "מנה"}) {
		t.Errorf("opening = %v, want the category pool", got)
	}

	// A sweet, cold board should lead somewhere sweet and cold.
	sweet := f.impostorHints("אוכל", []string{"מתוק", "קר"})
	if len(sweet) == 0 || sweet[0] != "קיץ" {
		t.Errorf("a sweet cold board led with %v, want קיץ first", sweet)
	}
	if at, warm := slices.Index(sweet, "פירות"), slices.Index(sweet, "חם"); at < 0 || at > warm {
		t.Errorf("פירות did not beat חם on a sweet board: %v", sweet)
	}

	// A different board leads somewhere else, which is the whole point.
	soup := f.impostorHints("אוכל", []string{"חם", "כף"})
	if len(soup) == 0 || soup[0] != "חורף" {
		t.Errorf("a hot board led with %v, want חורף first", soup)
	}
	if summer := slices.Index(soup, "קיץ"); summer == 0 {
		t.Errorf("a hot board led with summer: %v", soup)
	}

	// Never repeat what is already said, from either pool.
	for _, hint := range f.impostorHints("אוכל", []string{"מתוק", "ארוחה"}) {
		if hint == "מתוק" || hint == "ארוחה" {
			t.Errorf("%q is already on the board", hint)
		}
	}
}

// The rule that keeps bots from hunting people: the dataset holds the words
// bots write, never the words players write, so a hint nobody curated carries
// no opinion and must not count against its author.
func TestAHintNobodyCuratedIsNeverSuspicious(t *testing.T) {
	f := loadHintTables([]byte(fixture))

	// What a person might write for גלידה. None of it is in any pool.
	for _, human := range []string{"נמס", "תלת", "שמחה", "קונוס"} {
		if got := f.citizenSuspicion(human, "גלידה"); got != 0 {
			t.Errorf("citizen: %q scored %d, want 0 — it is a player's own word", human, got)
		}
		if got := f.boardSuspicion(human, []string{"מתוק", "קר"}); got != 0 {
			t.Errorf("board: %q scored %d, want 0", human, got)
		}
	}

	// A board of words nobody curated cannot convict anyone either.
	if got := f.boardSuspicion("מתוק", []string{"שמחה", "קונוס"}); got != 0 {
		t.Errorf("a board of unknown words scored %d, want 0", got)
	}
}

func TestSuspicionCatchesAHintFromTheWrongCluster(t *testing.T) {
	f := loadHintTables([]byte(fixture))

	// Hints from גלידה's own pool, and hints that keep company with them.
	for _, fits := range []string{"מתוק", "קר", "קיץ", "וניל"} {
		if got := f.citizenSuspicion(fits, "גלידה"); got != 0 {
			t.Errorf("%q belongs beside גלידה but scored %d", fits, got)
		}
	}
	// Three levels, and the middle one is the useful part. כף only ever turns
	// up in soup, so beside גלידה it is plainly out of place. חורף is a winter
	// word, but תה is both sweet and wintery, so it touches one edge of גלידה
	// and earns doubt rather than blame — which is what a hint from outside
	// usually looks like.
	for hint, want := range map[string]int{"כף": 2, "חורף": 1, "קיץ": 0} {
		if got := f.citizenSuspicion(hint, "גלידה"); got != want {
			t.Errorf("citizenSuspicion(%q, גלידה) = %d, want %d", hint, got, want)
		}
	}

	// Without the word, the board does the same work: a cold sweet board and a
	// hint that only ever turns up in soup.
	if got := f.boardSuspicion("כף", []string{"מתוק", "קר", "קיץ"}); got == 0 {
		t.Error("a soup word passed unnoticed on a dessert board")
	}
	if got := f.boardSuspicion("קיץ", []string{"מתוק", "קר"}); got != 0 {
		t.Errorf("a dessert word on a dessert board scored %d, want 0", got)
	}
}
