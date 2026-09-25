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
	// minInnerSecret is the shortest secret matched anywhere inside a hint.
	// Shorter ones (ים, דג, פיל) sit inside too many unrelated words, so they
	// are matched only at the start, after any prefix letters.
	minInnerSecret = 4
)

// presentationForms folds the Hebrew presentation forms (U+FB1D–FB4F) to
// the letters they draw, so "בּית" typed with precomposed characters still
// matches, repeats and gets blocked like "בית". The standard library has no
// NFKC; this block is all a Hebrew keyboard or a copy-paste can produce.
var presentationForms = strings.NewReplacer(
	"\uFB1D", "י", "\uFB1F", "ײ", "\uFB20", "ע", "\uFB21", "א", "\uFB22", "ד", "\uFB23", "ה",
	"\uFB24", "כ", "\uFB25", "ל", "\uFB26", "ם", "\uFB27", "ר", "\uFB28", "ת",
	"\uFB2A", "ש", "\uFB2B", "ש", "\uFB2C", "ש", "\uFB2D", "ש", "\uFB2E", "א", "\uFB2F", "א", "\uFB30", "א",
	"\uFB31", "ב", "\uFB32", "ג", "\uFB33", "ד", "\uFB34", "ה", "\uFB35", "ו", "\uFB36", "ז",
	"\uFB38", "ט", "\uFB39", "י", "\uFB3A", "ך", "\uFB3B", "כ", "\uFB3C", "ל", "\uFB3E", "מ",
	"\uFB40", "נ", "\uFB41", "ס", "\uFB43", "ף", "\uFB44", "פ", "\uFB46", "צ", "\uFB47", "ק",
	"\uFB48", "ר", "\uFB49", "ש", "\uFB4A", "ת", "\uFB4B", "ו", "\uFB4C", "ב", "\uFB4D", "כ",
	"\uFB4E", "פ", "\uFB4F", "אל",
)

// cleanHint drops invisible formatting characters (zero-width, bidi marks)
// and turns blank-looking fillers into spaces, so neither can smuggle a
// second word past the one-word rule or split the secret word apart.
func cleanHint(s string) string {
	return strings.Map(func(r rune) rune {
		switch {
		case unicode.Is(unicode.Cf, r):
			return -1
		case r == '\u2800' || r == '\u3164' || r == '\u115F' || r == '\u1160' || r == '\uFFA0':
			return ' '
		}
		return r
	}, s)
}

var finalLetters = strings.NewReplacer("ך", "כ", "ם", "מ", "ן", "נ", "ף", "פ", "ץ", "צ")

// normalizeWord keeps letters and digits only, dropping niqqud, geresh,
// gershayim, maqaf, hyphens and other punctuation, lowercases, and maps final
// letters to their regular forms. Spelling is otherwise strict.
// Hebrew presentation forms are folded first (presentationForms).
func normalizeWord(s string) string {
	var b strings.Builder
	for _, r := range presentationForms.Replace(s) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(unicode.ToLower(r))
		}
	}
	return finalLetters.Replace(b.String())
}

// IsPrefixedForm reports whether long is short carrying only Hebrew prefix
// letters (אותיות שימוש). Exposed for the content blocklist, which has to
// catch "והזונה" without catching "מאזין".
func IsPrefixedForm(long, short string) bool { return isPrefixed(long, short) }

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

// hintContainsSecret applies only to citizens; the impostor does not know the
// word. For a two-word secret, neither the full phrase nor either visible word
// may be used as the one-word hint. Short components are matched only as exact
// or Hebrew-prefixed forms, avoiding false positives such as בן inside מבנה.
func hintContainsSecret(hint, secret string) bool {
	h := normalizeWord(hint)
	matches := func(s string, allowInner bool) bool {
		s = normalizeWord(s)
		if s == "" {
			return false
		}
		if allowInner && len([]rune(s)) >= minInnerSecret {
			return strings.Contains(h, s)
		}
		return h == s || isPrefixed(h, s)
	}

	// A phrase typed without spaces is still the phrase.
	if matches(secret, true) {
		return true
	}
	parts := strings.Fields(secret)
	if len(parts) <= 1 {
		return false
	}
	for _, part := range parts {
		if matches(part, len([]rune(normalizeWord(part))) >= minInnerSecret) {
			return true
		}
	}
	return false
}

// sameHint treats hints as duplicates when they are equal or one is the other
// with prefix letters, so "הבית" repeats "בית" but "לבית" does not repeat "הבית".
func sameHint(a, b string) bool {
	a, b = normalizeWord(a), normalizeWord(b)
	return a == b || isPrefixed(a, b) || isPrefixed(b, a)
}

// guessMatches accepts the secret word or one of its configured alternate
// spellings, optionally with Hebrew prefix letters. Spacing and punctuation
// are already ignored by normalizeWord, so aliases are only needed when the
// spelling itself differs.
func guessMatches(guess, secret string, aliases ...string) bool {
	g := normalizeWord(guess)
	matches := func(candidate string) bool {
		s := normalizeWord(candidate)
		return g == s || isPrefixed(g, s)
	}
	if matches(secret) {
		return true
	}
	for _, alias := range aliases {
		if matches(alias) {
			return true
		}
	}
	return false
}
