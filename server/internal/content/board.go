package content

import (
	"math"
	"slices"
	"strings"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

// BoardHint is one played hint, as everyone at the table sees it.
type BoardHint struct {
	PlayerID string
	Text     string
}

// Suspicion reads a round and scores how out of place each player's hint looks
// beside the others.
//
// It is given the board and nothing else: the category, who said what, in the
// order it was said. Not the secret word, not who is the impostor, not who is a
// person and who is a bot — it has no parameter for any of them, which is why
// the same board always reads the same way. That is the whole architecture.
//
// Each hint is judged against the round built without it, so no hint props
// itself up, and the scores are relative to the round rather than to a
// threshold: a table where nothing connects suspects nobody in particular.
func Suspicion(category string, board []BoardHint) map[string]float64 {
	return tables.suspicion(category, board)
}

func (t hintTables) suspicion(category string, board []BoardHint) map[string]float64 {
	out := make(map[string]float64, len(board))
	if len(board) < 2 {
		for _, h := range board {
			out[h.PlayerID] = 0
		}
		return out
	}
	raw := make(map[string]float64, len(board))
	sum, judged := 0.0, 0
	for _, h := range board {
		// Leave one out: does this hint reach the round built without it?
		//
		// Reaches it or does not, never how far. Two bots drawing on the same
		// curated pool are joined by direct evidence and would out-score any
		// outsider on weight alone, so counting strength would measure who
		// shares a vocabulary with whom rather than who fits the round — and
		// a person reaching the board through the shape of a word would come
		// out worse than one who reached nothing at all.
		reach := false
		for _, other := range board {
			if other.PlayerID != h.PlayerID && t.affinity(h.Text, other.Text) {
				reach = true
				break
			}
		}
		// A hint the category lists as broad says little about any word in it,
		// which is what somebody with nothing to go on reaches for. Curating it
		// as broad is itself something we know, and it has to be settled before
		// the guard below or it never gets asked: half the fallback hints
		// appear in no citizen pool, so the graph has no other opinion on them
		// and the signal would be dropped for exactly the hints it is for.
		vague := slices.ContainsFunc(t.fallback[category], func(f string) bool { return sameWord(f, h.Text) })

		// Whether there is anything to judge this hint on at all. A word the
		// graph has never heard of, which reaches nothing on the board through
		// its shape and is not one the category calls broad, is a word we know
		// nothing about — and silence is not evidence. The one person at the
		// table is the one player whose words are guaranteed to be missing from
		// a graph built out of what bots say, so reading that silence as guilt
		// would hunt them by construction: measured at 78% before this guard
		// existed.
		if !t.known(h.Text) && !reach && !vague {
			continue
		}
		// Broad or apart, never both. A hint the category calls broad is one
		// that was always going to reach nothing in particular — that is what
		// makes it broad — so charging it for standing apart as well would be
		// charging it twice for one fact, and it read as worse than a hint
		// from another round entirely. Saying little is not the same as saying
		// something that does not belong.
		score := 0.0
		switch {
		case vague:
			score = vaguenessWeight
		case !reach:
			score = apartWeight
		}
		raw[h.PlayerID] = score
		sum += raw[h.PlayerID]
		judged++
	}
	if judged == 0 {
		for _, h := range board {
			out[h.PlayerID] = 0
		}
		return out
	}

	// Centre on the round. What matters is standing apart from this table, not
	// clearing some absolute bar, so a round nobody can connect — four hints in
	// words the graph has never seen — comes out flat instead of accusing
	// everyone at once.
	mean := sum / float64(judged)
	for _, h := range board {
		// A hint there was nothing to judge sits where the round sits: neither
		// accused nor cleared.
		score, ok := raw[h.PlayerID]
		if !ok {
			score = mean
		}
		out[h.PlayerID] = score - mean
	}
	return out
}

const (
	// Standing apart from the round is the reading; being broad adds to it.
	apartWeight     = 1.0
	vaguenessWeight = 0.5
	// stemRunes is the shortest run of letters two words must share before the
	// shape of them counts as evidence, and minStemWord keeps short words out
	// of that rule — three letters inside a four-letter word is most of the
	// word. Short hints are common in Hebrew and would be unreachable
	// otherwise, so one word wholly inside another counts as well.
	stemRunes    = 3
	minStemWord  = 4
	minWholeWord = 2
)

// affinity reports whether two played hints look like they belong to the same
// round. It knows nothing about who wrote either one.
func (t hintTables) affinity(a, b string) bool {
	// Hebrew carries meaning in the stem, so איטלקי reaches איטליה and גבינות
	// reaches גבינה. That is the only thing that speaks for a word nobody
	// curated, which is to say for most of what a person writes.
	return sameWord(a, b) || t.linked(a, b) || sharesStem(a, b)
}

func sharesStem(a, b string) bool {
	x := []rune(game.NormalizeWord(a))
	y := []rune(game.NormalizeWord(b))
	// גבינות around גבינה, קרירות around קר.
	if len(x) >= minWholeWord && len(y) >= minWholeWord {
		if strings.Contains(string(x), string(y)) || strings.Contains(string(y), string(x)) {
			return true
		}
	}
	if len(x) < minStemWord || len(y) < minStemWord {
		return false
	}
	for i := 0; i+stemRunes <= len(x); i++ {
		run := string(x[i : i+stemRunes])
		for j := 0; j+stemRunes <= len(y); j++ {
			if string(y[j:j+stemRunes]) == run {
				return true
			}
		}
	}
	return false
}

// VoteOdds turns suspicion into the chance of each candidate being voted for.
//
// Softmax with a temperature, so the reading tilts the table rather than
// settling it. A bot that always voted for its top suspect would be a better
// player than the person across from it and would vote the same way every
// round.
func VoteOdds(scores map[string]float64, candidates []string, temperature float64) []float64 {
	odds := make([]float64, len(candidates))
	total := 0.0
	for i, c := range candidates {
		odds[i] = math.Exp(scores[c] / temperature)
		total += odds[i]
	}
	for i := range odds {
		odds[i] /= total
	}
	return odds
}
