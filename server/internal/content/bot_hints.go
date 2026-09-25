package content

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"slices"
	"sort"
	"strings"
	"unicode"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

// Bot hints (docs/bot-hints.md). Two pools, kept apart on purpose:
//
//   - citizen hints are keyed by public category plus secret word. A citizen
//     bot knows both; an impostor's View carries no secret word at all, so it
//     cannot reach this map even by mistake — the separation is the engine's,
//     not a rule bots are trusted to follow.
//   - impostorFallback and shared are keyed by category, which is public.
//
//go:embed bot_hints.json
var botHintsJSON []byte

type botHintFile struct {
	Version      int                 `json:"version"`
	GuessAliases map[string][]string `json:"guessAliases,omitempty"`
	Categories   []struct {
		ID                    string              `json:"id"`
		Name                  string              `json:"name"`
		ImpostorFallbackHints []string            `json:"impostorFallbackHints"`
		CitizenHints          map[string][]string `json:"citizenHints,omitempty"` // v1 compatibility
		Clusters              []struct {
			Name  string   `json:"name"`
			Words []string `json:"words"`
			Hints []string `json:"hints"`
		} `json:"clusters,omitempty"`
	} `json:"categories"`
}

// hintTables is everything derived from the dataset. It is a value rather than
// a pile of package variables so that the derivation can be exercised against a
// fixture, instead of only against whatever the real file happens to hold.
type hintTables struct {
	citizen  map[string]map[string][]string       // category name -> secret word -> hints
	fallback map[string][]string                  // category name -> hints
	shared   map[string][]string                  // category name -> hints used by 2+ words
	together map[string]map[string]map[string]int // category -> hint -> hint -> pools they share
	aliases  map[string][]string                  // secret word -> accepted guess spellings
}

var tables = loadHintTables(botHintsJSON)

func loadHintTables(raw []byte) hintTables {
	var file botHintFile
	if err := json.Unmarshal(raw, &file); err != nil {
		panic(fmt.Sprintf("bot_hints.json: %v", err))
	}
	t := hintTables{
		citizen:  map[string]map[string][]string{},
		fallback: map[string][]string{},
		shared:   map[string][]string{},
		together: map[string]map[string]map[string]int{},
		aliases:  map[string][]string{},
	}
	for word, aliases := range file.GuessAliases {
		t.aliases[word] = slices.Clone(aliases)
	}
	appearances := map[string]map[string]int{} // category -> hint -> words using it
	for _, c := range file.Categories {
		t.fallback[c.Name] = c.ImpostorFallbackHints
		appearances[c.Name] = map[string]int{}
		t.citizen[c.Name] = map[string][]string{}
		// Scoped by category: the same hint means different things next to
		// different words, and a link from another category is noise here.
		together := map[string]map[string]int{}
		t.together[c.Name] = together
		addWord := func(word string, hints []string) {
			t.citizen[c.Name][word] = slices.Clone(hints)
			for _, hint := range hints {
				appearances[c.Name][hint]++
				key := game.NormalizeWord(hint)
				if together[key] == nil {
					together[key] = map[string]int{}
				}
				for _, other := range hints {
					if other != hint {
						together[key][game.NormalizeWord(other)]++
					}
				}
			}
		}
		for word, hints := range c.CitizenHints {
			addWord(word, hints)
		}
		for _, cluster := range c.Clusters {
			for _, word := range cluster.Words {
				addWord(word, cluster.Hints)
			}
		}
	}
	for category, counts := range appearances {
		for hint, n := range counts {
			// A hint that belongs to exactly one word is that word's signature.
			// Letting the impostor reach for it would make it better than any
			// human in the same seat, so the impostor's vocabulary is only what
			// the category shares.
			if n >= 2 {
				t.shared[category] = append(t.shared[category], hint)
			}
		}
		sort.Strings(t.shared[category])
	}
	return t
}

// linked reports whether the category's graph pairs these two hints, however
// either of them happens to be spelled.
func (t hintTables) linked(category, a, b string) bool {
	return t.together[category][game.NormalizeWord(a)][game.NormalizeWord(b)] > 0
}

// known reports whether the category's graph has anything to say about a hint.
func (t hintTables) known(category, hint string) bool {
	return len(t.together[category][game.NormalizeWord(hint)]) > 0
}

// CitizenHints are the hints for a secret word in its public category, in file
// order. Category is part of the key because a useful word may intentionally
// appear in more than one category with different clue context. Empty for an
// impostor's view, which carries no secret word.
func CitizenHints(category, word string) []string {
	if category == "" || word == "" {
		return nil
	}
	return slices.Clone(tables.citizen[category][word])
}

// GuessAliases returns accepted alternate spellings for a secret. They are
// never shown to players; they only make the caught impostor's final guess
// tolerant of common Hebrew transliterations and legacy spellings.
func GuessAliases(word string) []string {
	return slices.Clone(tables.aliases[word])
}

// ImpostorHints are what a bot may say when it does not know the word, best
// first. It takes the category and the hints already on the board — public
// knowledge, all of it — and never the secret word, which is why it cannot be
// asked for one.
//
// With nothing on the board it can only be broad, which is the same corner a
// human impostor is in when they open. Each hint that lands gives it more to
// work with, and the same asymmetry is what makes going first hard.
func ImpostorHints(category string, seen []string) []string {
	return tables.impostorHints(category, seen)
}

func (t hintTables) impostorHints(category string, seen []string) []string {
	fallback := slices.Clone(t.fallback[category])
	if len(seen) == 0 {
		return fallback
	}
	type scored struct {
		hint  string
		score int
	}
	var ranked []scored
	for _, hint := range t.shared[category] {
		if slices.Contains(seen, hint) {
			continue // Already said; the engine would refuse it anyway.
		}
		score := 0
		for _, said := range seen {
			if t.linked(category, hint, said) {
				score += t.together[category][game.NormalizeWord(hint)][game.NormalizeWord(said)]
			}
		}
		if score > 0 {
			ranked = append(ranked, scored{hint, score})
		}
	}
	// Strongest first, and alphabetical within a tie so the order is the
	// board's doing and not the map's.
	sort.SliceStable(ranked, func(i, j int) bool {
		if ranked[i].score != ranked[j].score {
			return ranked[i].score > ranked[j].score
		}
		return ranked[i].hint < ranked[j].hint
	})
	out := make([]string, 0, len(ranked)+len(fallback))
	for _, r := range ranked {
		out = append(out, r.hint)
	}
	// The broad ones stay on the end: a bot that finds nothing in the board
	// still has to say something.
	for _, hint := range fallback {
		if !slices.Contains(out, hint) && !slices.Contains(seen, hint) {
			out = append(out, hint)
		}
	}
	return out
}

// UsableHint reports whether a bot may submit this hint for this word: the
// engine's rules, so that a curated pool cannot contain something a real turn
// would refuse. Pass an empty secret for the impostor, who is not checked
// against the word.
func UsableHint(hint, secret string) bool {
	switch {
	case hint == "" || len([]rune(hint)) > game.MaxHintRunes:
		return false
	case Blocked(hint):
		return false
	}
	if strings.ContainsFunc(hint, unicode.IsSpace) {
		return false // The engine's one-word rule.
	}
	if secret == "" {
		return true
	}
	return !containsWord(hint, secret)
}

// containsWord mirrors the engine's secret-word rule, including two-word
// secrets and the original handling of short single-word secrets.
func containsWord(hint, secret string) bool {
	h := game.NormalizeWord(hint)
	matchesWhole := func(candidate string) bool {
		s := game.NormalizeWord(candidate)
		switch {
		case s == "":
			return false
		case len([]rune(s)) >= 4:
			return strings.Contains(h, s)
		}
		if h == s || game.IsPrefixedForm(h, s) {
			return true
		}
		// Preserve the engine's historical "short stem at the start after
		// prefixes" behavior, e.g. פיל -> פילים and דג -> הדגים.
		hr := []rune(h)
		const prefixes = "והבכלמש"
		for i := 0; i <= 3 && i < len(hr); i++ {
			if i > 0 && !strings.ContainsRune(prefixes, hr[i-1]) {
				break
			}
			if strings.HasPrefix(string(hr[i:]), s) {
				return true
			}
		}
		return false
	}
	if matchesWhole(secret) {
		return true
	}
	parts := strings.Fields(secret)
	if len(parts) <= 1 {
		return false
	}
	for _, part := range parts {
		p := game.NormalizeWord(part)
		if p == "" {
			continue
		}
		if len([]rune(p)) >= 4 {
			if strings.Contains(h, p) {
				return true
			}
		} else if h == p || game.IsPrefixedForm(h, p) {
			return true
		}
	}
	return false
}

func sameWord(a, b string) bool { return game.NormalizeWord(a) == game.NormalizeWord(b) }
