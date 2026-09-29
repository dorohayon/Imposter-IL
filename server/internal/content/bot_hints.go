package content

import (
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
type botHintFile struct {
	Version      int                 `json:"version"`
	GuessAliases map[string][]string `json:"guessAliases,omitempty"`
	Categories   []struct {
		ID                    string              `json:"id"`
		Name                  string              `json:"name"`
		Words                 []string            `json:"words"`
		ImpostorFallbackHints []string            `json:"impostorFallbackHints"`
		BotHints              map[string][]string `json:"botHints"`
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

// Every language's hints in one set of tables: they are keyed by the public
// category name, which differs between languages.
var tables = loadHintTables(languageRaws()...)

func languageRaws() [][]byte {
	var out [][]byte
	for _, code := range Languages() {
		raw, err := languageFiles.ReadFile("languages/" + code + ".json")
		if err != nil {
			panic(err)
		}
		out = append(out, raw)
	}
	return out
}

func loadHintTables(raws ...[]byte) hintTables {
	t := hintTables{
		citizen:  map[string]map[string][]string{},
		fallback: map[string][]string{},
		shared:   map[string][]string{},
		together: map[string]map[string]map[string]int{},
		aliases:  map[string][]string{},
	}
	for _, raw := range raws {
		t.add(raw)
	}
	return t
}

func (t hintTables) add(raw []byte) {
	var file botHintFile
	if err := json.Unmarshal(raw, &file); err != nil {
		panic(fmt.Sprintf("language file: %v", err))
	}
	// Older shapes (clusters, citizenHints) parse without error into empty
	// categories, so a stray one would silently leave the bots mute.
	if file.Version != FormatVersion {
		panic(fmt.Sprintf("language file: version %d, want %d", file.Version, FormatVersion))
	}
	for word, aliases := range file.GuessAliases {
		t.aliases[word] = slices.Clone(aliases)
	}
	appearances := map[string]map[string]int{} // category -> hint -> words using it
	words := map[string][]string{}             // category -> its secret words
	for _, c := range file.Categories {
		words[c.Name] = c.Words
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
		for word, hints := range c.BotHints {
			addWord(word, hints)
		}
	}
	for category, counts := range appearances {
		for hint, n := range counts {
			// A hint that belongs to exactly one word is that word's signature.
			// Letting the impostor reach for it would make it better than any
			// human in the same seat, so the impostor's vocabulary is only what
			// the category shares.
			//
			// Nor a hint that is itself a secret of the category: the impostor's
			// hint is never checked against the word, so it could say the
			// answer out loud (משרד, when the secret is משרד).
			givesAway := slices.ContainsFunc(words[category], func(w string) bool {
				return sameWord(hint, w) || containsWord(hint, w)
			})
			if n >= 2 && !givesAway {
				t.shared[category] = append(t.shared[category], hint)
			}
		}
		sort.Strings(t.shared[category])
	}
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
// order. Category stays part of the key so the data follows the same public
// context the bot sees. Empty for an impostor's view, which carries no secret
// word.
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

// containsWord is the engine's secret-word rule, the one a real turn applies.
func containsWord(hint, secret string) bool { return game.HintContainsSecret(hint, secret) }

func sameWord(a, b string) bool { return game.NormalizeWord(a) == game.NormalizeWord(b) }
