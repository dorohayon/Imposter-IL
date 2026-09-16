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

// minSubstringRunes is the shortest entry matched inside a longer word. Short
// entries match only as whole words, so an innocent word that happens to
// contain two or three of the same letters is not refused.
const minSubstringRunes = 4

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
		// Shorter entries still match with Hebrew prefix letters in front.
		if strings.HasSuffix(normalized, word) && len(normalized) > len(word) {
			return true
		}
	}
	return false
}
