// Package content holds the approved categories and secret words.
package content

import (
	"embed"
	"encoding/json"
	"fmt"
	"maps"
	"math/rand/v2"
	"slices"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

type Category struct {
	ID    string
	Name  string
	Words []string
}

// FormatVersion is the shape of languages/<code>.json: flat word lists with
// eight bot hints per word (docs/bot-hints.md). Other versions are refused.
const FormatVersion = 3

// DefaultLanguage is what a request without a language plays in: every app
// released before languages existed speaks Hebrew.
const DefaultLanguage = "he"

// Language is one language's content, read from languages/<code>.json
// (docs/localization.md). Adding a language is adding that file.
type Language struct {
	Code string
	// Name is the language in itself ("עברית", "English").
	Name       string
	Categories []Category
	Reactions  []Reaction
	Bots       Bots
}

// Bots are the staging bots' names and last-resort hints in one language.
type Bots struct {
	Prefix        string              `json:"prefix"`
	Names         map[string][]string `json:"names"` // "f" and "m", matching the avatars
	FallbackHints []string            `json:"fallbackHints"`
	UnknownGuess  string              `json:"unknownGuess"`
}

//go:embed languages/*.json
var languageFiles embed.FS

var languages = loadLanguages()

func loadLanguages() map[string]*Language {
	entries, err := languageFiles.ReadDir("languages")
	if err != nil {
		panic(err)
	}
	out := map[string]*Language{}
	for _, e := range entries {
		raw, err := languageFiles.ReadFile("languages/" + e.Name())
		if err != nil {
			panic(err)
		}
		var file struct {
			Version    int    `json:"version"`
			Language   string `json:"language"`
			Name       string `json:"name"`
			Categories []struct {
				ID    string   `json:"id"`
				Name  string   `json:"name"`
				Words []string `json:"words"`
			} `json:"categories"`
			Reactions []Reaction `json:"reactions"`
			Bots      Bots       `json:"bots"`
		}
		if err := json.Unmarshal(raw, &file); err != nil {
			panic(fmt.Sprintf("%s: %v", e.Name(), err))
		}
		if file.Version != FormatVersion {
			panic(fmt.Sprintf("%s: version %d, want %d (docs/bot-hints.md)", e.Name(), file.Version, FormatVersion))
		}
		lang := &Language{Code: file.Language, Name: file.Name, Bots: file.Bots,
			Reactions: append(slices.Clone(emojiReactions), file.Reactions...)}
		for _, c := range file.Categories {
			category := Category{ID: c.ID, Name: c.Name, Words: slices.Clone(c.Words)}
			lang.Categories = append(lang.Categories, category)
		}
		out[lang.Code] = lang
	}
	return out
}

// For returns a language's content. An empty code is DefaultLanguage.
func For(code string) (*Language, bool) {
	if code == "" {
		code = DefaultLanguage
	}
	l, ok := languages[code]
	return l, ok
}

// Languages lists the language codes, sorted.
func Languages() []string {
	return slices.Sorted(maps.Keys(languages))
}

// KnownCategory reports whether id is a category in any language. Purchases
// are keyed by category id, whatever language the player plays in.
func KnownCategory(id string) bool {
	for _, l := range languages {
		if slices.ContainsFunc(l.Categories, func(c Category) bool { return c.ID == id }) {
			return true
		}
	}
	return false
}

// ValidIDs reports whether ids is non-empty and names only categories of
// this language.
func (l *Language) ValidIDs(ids []string) bool {
	if len(ids) == 0 {
		return false
	}
	for _, id := range ids {
		if !slices.ContainsFunc(l.Categories, func(c Category) bool { return c.ID == id }) {
			return false
		}
	}
	return true
}

// Pick chooses a random category-word pair from the selected categories of
// language code and returns it with its category name. The same secret may
// intentionally appear in different categories because the public category
// changes what constitutes a useful clue.
func Pick(code string, ids []string, rng *rand.Rand) (categoryName, word string, ok bool) {
	l, found := For(code)
	if !found {
		return "", "", false
	}
	var pool []Category
	total := 0
	for _, c := range l.Categories {
		if slices.Contains(ids, c.ID) {
			pool = append(pool, c)
			total += len(c.Words)
		}
	}
	if total == 0 {
		return "", "", false
	}
	n := rng.IntN(total)
	for _, c := range pool {
		if n < len(c.Words) {
			return c.Name, c.Words[n], true
		}
		n -= len(c.Words)
	}
	return "", "", false
}

// CategoryNamed finds a category by its public name, in any language. A
// game carries the name, not the id.
func CategoryNamed(name string) (Category, bool) {
	for _, l := range languages {
		for _, c := range l.Categories {
			if c.Name == name {
				return c, true
			}
		}
	}
	return Category{}, false
}

type Reaction struct {
	ID   string `json:"id"`   // stable id sent as reactionId
	Text string `json:"text"` // emoji or structured message shown in the app
}

// The approved reactions (docs/decisions.md): six emoji, shared by every
// language, then each language's four structured messages.
var emojiReactions = []Reaction{
	{"laugh", "😂"},
	{"thinking", "🤔"},
	{"eyes", "👀"},
	{"surprised", "😮"},
	{"applause", "👏"},
	{"eye_roll", "🙄"},
}

// Policy is the game policy: the approved reactions and the blocked-word list
// the app stores require for user-generated content (blocklist.go).
func Policy() game.Policy {
	return game.Policy{
		HintInappropriate: Blocked,
		ValidReaction:     ValidReaction,
		GuessAliases:      GuessAliases,
	}
}

// ValidReaction reports whether id is an approved reaction id. Every language
// has the same ids (TestLanguagesAgree).
func ValidReaction(id string) bool {
	l, _ := For(DefaultLanguage)
	return slices.ContainsFunc(l.Reactions, func(r Reaction) bool { return r.ID == id })
}
