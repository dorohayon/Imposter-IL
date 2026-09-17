package content

import (
	_ "embed"
	"strings"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

// Hints and nicknames are free text written by one player and shown to up to
// seven strangers. App Store Review Guideline 1.2 and Google Play's UGC policy
// both require an app that does this to filter objectionable content, so the
// "no blocking" decision in docs/decisions.md could not survive review.
//
// The mechanism lives here; the list itself is still an open decision
// (docs/open-decisions.md) and is edited in blocked_words.txt without touching
// Go code.

//go:embed blocked_words.txt
var blockedWordsFile string

const (
	// minSubstringRunes is the shortest entry matched inside a longer word.
	// Four was too short: "cock" refused peacock and cocktail, "rape" refused
	// grape and scrape, "dick" refused dickens. Six is long enough that
	// accidental containment is implausible, and still catches the entries
	// people run together, like שרמוטה or motherfucker.
	minSubstringRunes = 6
	// minPrefixStemRunes is the shortest entry that Hebrew prefix letters may
	// precede. With three, מ + זין refused מזין — an ordinary word, and a
	// plausible hint in the food category.
	minPrefixStemRunes = 4
)

var blockedWords = parseBlocked(blockedWordsFile)

func parseBlocked(file string) []string {
	var out []string
	for line := range strings.Lines(file) {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if word := game.NormalizeWord(line); word != "" {
			out = append(out, word)
		}
	}
	return out
}

// Blocked reports whether text contains a blocked word. It normalises the way
// the game's own word rules do, so prefixed forms ("והזונה") are caught along
// with the base word.
func Blocked(text string) bool {
	normalized := game.NormalizeWord(text)
	if normalized == "" {
		return false
	}
	for _, word := range blockedWords {
		if normalized == word {
			return true
		}
		if len([]rune(word)) >= minSubstringRunes && strings.Contains(normalized, word) {
			return true
		}
		// Shorter entries still match with Hebrew prefix letters in front —
		// but only those, and only when the stem is long enough that the
		// combination is not an ordinary word in its own right.
		if len([]rune(word)) >= minPrefixStemRunes &&
			game.IsPrefixedForm(normalized, word) {
			return true
		}
	}
	return false
}
