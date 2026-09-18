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
//   - citizenHints is keyed by the secret word, and a citizen bot knows the
//     word because the game tells it. The impostor's View carries no secret
//     word at all, so an impostor bot cannot reach this map even by mistake —
//     the separation is the engine's, not a rule bots are trusted to follow.
//   - impostorFallback and shared are keyed by category, which is public.
//
//go:embed bot_hints.json
var botHintsJSON []byte

type botHintFile struct {
	Version    int `json:"version"`
	Categories []struct {
		ID                    string              `json:"id"`
		Name                  string              `json:"name"`
		ImpostorFallbackHints []string            `json:"impostorFallbackHints"`
		CitizenHints          map[string][]string `json:"citizenHints"`
	} `json:"categories"`
}

// hintTables is everything derived from the dataset. It is a value rather than
// a pile of package variables so that the derivation can be exercised against a
// fixture, instead of only against whatever the real file happens to hold.
type hintTables struct {
	citizen  map[string][]string       // secret word -> hints
	fallback map[string][]string       // category name -> hints
	shared   map[string][]string       // category name -> hints used by 2+ words
	together map[string]map[string]int // hint -> hint -> pools they share
}

var tables = loadHintTables(botHintsJSON)

func loadHintTables(raw []byte) hintTables {
	var file botHintFile
	if err := json.Unmarshal(raw, &file); err != nil {
		panic(fmt.Sprintf("bot_hints.json: %v", err))
	}
	t := hintTables{
		citizen:  map[string][]string{},
		fallback: map[string][]string{},
		shared:   map[string][]string{},
		together: map[string]map[string]int{},
	}
	appearances := map[string]map[string]int{} // category -> hint -> words using it
	for _, c := range file.Categories {
		t.fallback[c.Name] = c.ImpostorFallbackHints
		appearances[c.Name] = map[string]int{}
		for word, hints := range c.CitizenHints {
			t.citizen[word] = hints
			for _, hint := range hints {
				appearances[c.Name][hint]++
				if t.together[hint] == nil {
					t.together[hint] = map[string]int{}
				}
				// Hints that share a word's pool describe the same thing. This
				// is what lets an impostor read the board: knowledge about the
				// language, gathered across every word, never about the word in
				// play.
				for _, other := range hints {
					if other != hint {
						t.together[hint][other]++
					}
				}
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

// CitizenHints are the hints for a secret word, in file order. Empty for a
// word with no curated pool, and for the empty string — which is what an
// impostor's View holds, so this cannot leak through a caller that forgets
// which role it is playing.
func CitizenHints(word string) []string {
	if word == "" {
		return nil
	}
	return slices.Clone(tables.citizen[word])
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
			score += t.together[hint][said]
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

// containsWord mirrors the engine's secret-word rule: a hint is refused when
// its normalised form contains the normalised word.
func containsWord(hint, secret string) bool {
	s := game.NormalizeWord(secret)
	return s != "" && strings.Contains(game.NormalizeWord(hint), s)
}
