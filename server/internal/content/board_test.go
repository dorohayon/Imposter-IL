package content

import (
	"math"
	"testing"
)

// The invariant the whole design rests on: the same category and the same
// board read the same way, whatever the round happens to be underneath. There
// is no parameter for the secret word, for who the impostor is, or for who is
// a person — so this checks the thing that could still go wrong, which is a
// score that moves when nothing public moved.
func TestTheReadingDependsOnNothingButTheBoard(t *testing.T) {
	f := loadHintTables([]byte(fixture))
	board := []BoardHint{
		{"a", "מתוק"}, {"b", "קר"}, {"c", "כף"}, {"d", "מילהשלאדם"},
	}
	want := f.suspicion("אוכל", board)

	// Every word in the fixture, played as the secret one. Nothing may move.
	for word := range f.citizen {
		got := f.suspicion("אוכל", board)
		for id, score := range want {
			if math.Abs(got[id]-score) > 1e-9 {
				t.Fatalf("the reading moved for %q when the word was %q", id, word)
			}
		}
	}

	// Shuffling who is a bot and who is a person is not something the reading
	// can see: only the text is passed, so relabelling the players moves the
	// scores with them and nothing else.
	relabelled := []BoardHint{
		{"human", "מתוק"}, {"bot1", "קר"}, {"bot2", "כף"}, {"bot3", "מילהשלאדם"},
	}
	got := f.suspicion("אוכל", relabelled)
	for i, h := range board {
		if math.Abs(got[relabelled[i].PlayerID]-want[h.PlayerID]) > 1e-9 {
			t.Errorf("%q read differently from %q for the same hint", relabelled[i].PlayerID, h.PlayerID)
		}
	}
}

// The behaviour that was missing: a hint is judged by whether it fits the
// round, not by who wrote it. A word the graph knows, played into a round it
// has nothing to do with, reads badly whoever played it.
func TestAHintFromTheWrongRoundReadsBadly(t *testing.T) {
	f := loadHintTables([]byte(fixture))
	board := []BoardHint{
		{"a", "מתוק"}, {"b", "קר"}, {"c", "קיץ"}, {"stranger", "כף"},
	}
	scores := f.suspicion("אוכל", board)
	for _, id := range []string{"a", "b", "c"} {
		if scores["stranger"] <= scores[id] {
			t.Errorf("a soup word on a dessert board (%.2f) did not read worse than %q (%.2f)",
				scores["stranger"], id, scores[id])
		}
	}

	// And a word nobody curated, which reaches the round only through its
	// shape, is not held against its author.
	board[3] = BoardHint{"stranger", "קרירות"}
	if reaching := f.suspicion("אוכל", board); reaching["stranger"] > 0 {
		t.Errorf("a stem that reaches the round still read as suspicious: %.2f",
			reaching["stranger"])
	}
}

// The line this design is built on, and the one it got wrong twice.
//
// A graph built out of what bots say cannot speak about what people write, and
// the one person at a table of bots is the one player whose words are
// guaranteed to be missing from it. Silence is not evidence: a hint there is
// nothing to say about sits exactly where the round sits.
//
// Both earlier attempts failed here — the first hunted a person whose hint
// fitted perfectly 78% of the time, and the second read a hint that reached
// the round through its shape as worse than one that reached nothing at all,
// because two bots drawing on one curated pool out-weigh any outsider.
func TestSilenceIsNotEvidence(t *testing.T) {
	f := loadHintTables([]byte(fixture))
	board := []BoardHint{
		{"a", "מתוק"}, {"b", "קר"}, {"c", "קיץ"}, {"person", "מסדרון"},
	}
	scores := f.suspicion("אוכל", board)
	if scores["person"] > 0 {
		t.Errorf("a word the graph has never heard read as suspicious: %.2f", scores["person"])
	}
	for _, id := range []string{"a", "b", "c"} {
		if scores["person"] > scores[id] {
			t.Errorf("the unheard-of word (%.2f) read worse than %q (%.2f)",
				scores["person"], id, scores[id])
		}
	}
}

// A round where nothing connects accuses nobody in particular, rather than
// everybody at once.
func TestARoundThatConnectsToNothingIsFlat(t *testing.T) {
	f := loadHintTables([]byte(fixture))
	flat := f.suspicion("אוכל", []BoardHint{
		{"a", "מסדרון"}, {"b", "פנסים"}, {"c", "ברזל"}, {"d", "שמיכה"},
	})
	for id, score := range flat {
		if math.Abs(score) > 1e-9 {
			t.Errorf("%q stood out (%.2f) in a round where nothing connects", id, score)
		}
	}
}

func TestVoteOddsAreAProbability(t *testing.T) {
	scores := map[string]float64{"a": 1.5, "b": 0, "c": -1.5}
	odds := VoteOdds(scores, []string{"a", "b", "c"}, 0.6)
	sum := 0.0
	for _, o := range odds {
		sum += o
	}
	if math.Abs(sum-1) > 1e-9 {
		t.Errorf("the odds sum to %.4f", sum)
	}
	if !(odds[0] > odds[1] && odds[1] > odds[2]) {
		t.Errorf("the order does not follow suspicion: %v", odds)
	}
	// Temperature is the difference between an opinion and a verdict.
	if sharp := VoteOdds(scores, []string{"a", "b", "c"}, 0.15); sharp[0] <= odds[0] {
		t.Errorf("a colder read was not more decided: %v vs %v", sharp, odds)
	}
}

// Half the curated fallback hints appear in no citizen pool, so the graph has
// nothing else to say about them. If the broad-hint signal is decided after
// the guard that drops unjudgeable hints, it never runs for exactly the hints
// it exists for — a round where the impostor reaches for a category word came
// out perfectly flat.
func TestABroadHintIsJudgedEvenWhenTheGraphIsSilent(t *testing.T) {
	f := loadHintTables([]byte(fixture))

	// מנה is in the fixture's fallback pool and in none of its citizen pools.
	if f.known("אוכל", "מנה") {
		t.Fatal("the fixture changed: מנה now appears in a citizen pool")
	}
	board := []BoardHint{
		{"a", "מתוק"}, {"b", "קר"}, {"c", "קיץ"}, {"broad", "מנה"},
	}
	scores := f.suspicion("אוכל", board)
	for _, id := range []string{"a", "b", "c"} {
		if scores["broad"] <= scores[id] {
			t.Errorf("the broad hint (%.2f) did not read worse than %q (%.2f)",
				scores["broad"], id, scores[id])
		}
	}

	// ארוחה too, and a round made only of broad hints still accuses nobody in
	// particular.
	flat := f.suspicion("אוכל", []BoardHint{{"a", "ארוחה"}, {"b", "מנה"}})
	for id, score := range flat {
		if math.Abs(score) > 1e-9 {
			t.Errorf("%q stood out (%.2f) where every hint is equally broad", id, score)
		}
	}
}

// The graph is keyed the way the game reads a word, not the way it happens to
// be spelled in the dataset. ג'ונגל and גונגל are one word to the engine, and
// before this the curated spelling could use the graph while the other was
// treated as a word nobody had ever heard of.
func TestSpellingDoesNotDecideWhetherAHintCanBeJudged(t *testing.T) {
	board := func(spelling string) []BoardHint {
		return []BoardHint{
			{"a", "פרווה"}, {"b", "טורף"}, {"c", "זנב"}, {"x", spelling},
		}
	}
	for _, pair := range [][2]string{
		{"ג'ונגל", "גונגל"},   // geresh dropped, as normalisation drops it
		{"טורף", "טורפ"},      // final letter written plain
		{"אפריקה", "אפריקה!"}, // punctuation
	} {
		curated := Suspicion("חיות", board(pair[0]))["x"]
		typed := Suspicion("חיות", board(pair[1]))["x"]
		if math.Abs(curated-typed) > 1e-9 {
			t.Errorf("%q read %+.2f but %q read %+.2f: spelling decided whether it could be judged",
				pair[0], curated, pair[1], typed)
		}
	}
}

// The same hint links to different hints in different categories; a link from
// one category must not count in another, or bots read the board wrongly.
func TestHintLinksStayInTheirCategory(t *testing.T) {
	f := loadHintTables([]byte(`{"version": 2, "categories": [
		{"id": "a", "name": "א", "impostorFallbackHints": [], "clusters": [
			{"name": "x", "words": ["ירח", "כוכב"], "hints": ["לילה", "שמיים"]}]},
		{"id": "b", "name": "ב", "impostorFallbackHints": [], "clusters": [
			{"name": "y", "words": ["מועדון", "פאב"], "hints": ["לילה", "מסיבה"]}]}]}`))
	if !f.linked("א", "לילה", "שמיים") || !f.linked("ב", "לילה", "מסיבה") {
		t.Fatal("a link inside its own category is missing")
	}
	if f.linked("א", "לילה", "מסיבה") || f.linked("ב", "לילה", "שמיים") {
		t.Fatal("a link leaked across categories")
	}
}
