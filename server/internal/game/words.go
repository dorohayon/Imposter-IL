package game

import (
	"strings"
	"unicode"
)

// Hebrew word rules from docs/decisions.md, tested against
// testdata/word_rules.json.

const (
	// Letters that can be attached in front of a Hebrew word (אותיות שימוש).
	prefixLetters    = "והבכלמש"
	maxPrefixLetters = 3
	minStemLetters   = 2
)

var finalLetters = strings.NewReplacer("ך", "כ", "ם", "מ", "ן", "נ", "ף", "פ", "ץ", "צ")

// normalizeWord keeps letters and digits only, dropping niqqud, geresh,
// gershayim, maqaf, hyphens and other punctuation, lowercases, and maps final
// letters to their regular forms. Spelling is otherwise strict.
// ponytail: no NFKC, so precomposed presentation forms (U+FB1D–FB4F) are not
// folded; add golang.org/x/text/unicode/norm if they show up in real input.
func normalizeWord(s string) string {
	var b strings.Builder
	for _, r := range s {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(unicode.ToLower(r))
		}
	}
	return finalLetters.Replace(b.String())
}

// NormalizeWord exposes the normalisation above to callers that match words
// against lists of their own, such as the content blocklist. Matching there
// has to fold spelling exactly the way the game's own rules do, or a word
// blocked in a hint would slip through in a nickname.
func NormalizeWord(s string) string { return normalizeWord(s) }

// isPrefixed reports whether long is short with 1 to maxPrefixLetters prefix
// letters in front, leaving at least minStemLetters letters.
func isPrefixed(long, short string) bool {
	l, s := []rune(long), []rune(short)
	n := len(l) - len(s)
	if n < 1 || n > maxPrefixLetters || len(s) < minStemLetters || string(l[n:]) != short {
		return false
	}
	return !strings.ContainsFunc(string(l[:n]), func(r rune) bool {
		return !strings.ContainsRune(prefixLetters, r)
	})
}

// hintContainsSecret applies only to citizens; the impostor does not know the word.
func hintContainsSecret(hint, secret string) bool {
	s := normalizeWord(secret)
	return s != "" && strings.Contains(normalizeWord(hint), s)
}

// sameHint treats hints as duplicates when they are equal or one is the other
// with prefix letters, so "הבית" repeats "בית" but "לבית" does not repeat "הבית".
func sameHint(a, b string) bool {
	a, b = normalizeWord(a), normalizeWord(b)
	return a == b || isPrefixed(a, b) || isPrefixed(b, a)
}

// guessMatches accepts the secret word, optionally with prefix letters.
func guessMatches(guess, secret string) bool {
	g, s := normalizeWord(guess), normalizeWord(secret)
	return g == s || isPrefixed(g, s)
}
