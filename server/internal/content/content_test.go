package content

import (
	"math/rand/v2"
	"slices"
	"strings"
	"testing"
	"unicode"
)

// allCategories is every language's categories, so each quality rule below
// holds for all of them.
func allCategories() []Category {
	var out []Category
	for _, code := range Languages() {
		l, _ := For(code)
		out = append(out, l.Categories...)
	}
	return out
}

func mustLanguage(t *testing.T, code string) *Language {
	t.Helper()
	l, ok := For(code)
	if !ok {
		t.Fatalf("no language %q", code)
	}
	return l
}

// scripts are the writing systems a secret may be spelled in; a language
// keeps to one, so a Hebrew word never carries Latin letters.
var scripts = []*unicode.RangeTable{unicode.Hebrew, unicode.Latin, unicode.Cyrillic, unicode.Arabic, unicode.Greek}

func scriptOf(r rune) *unicode.RangeTable {
	for _, s := range scripts {
		if unicode.Is(s, r) {
			return s
		}
	}
	return nil
}

// isSecret reports whether s is one or more plain words in script: letters,
// their marks, and the apostrophe or quote some spellings use (צ'אט, בקו"ם,
// don't). No digits, hyphens or maqaf: playable secrets are plain tokens.
func isSecret(s string, script *unicode.RangeTable) bool {
	parts := strings.Fields(s)
	if len(parts) < 1 || strings.Join(parts, " ") != s {
		return false
	}
	for _, r := range s {
		switch {
		case r == ' ' || r == '\'' || r == '"' || unicode.Is(unicode.Mn, r):
		case r == '\u05BE' || !unicode.Is(script, r): // the script's own geresh and gershayim pass
			return false
		}
	}
	return true
}

func TestCategoriesAreWellFormed(t *testing.T) {
	for _, code := range Languages() {
		l := mustLanguage(t, code)
		if l.Code != code || l.Name == "" {
			t.Errorf("languages/%s.json names itself %q (%q)", code, l.Code, l.Name)
		}
		script := scriptOf([]rune(l.Categories[0].Words[0])[0])
		ids := map[string]bool{}
		seen := map[string]bool{}
		total := 0
		for _, c := range l.Categories {
			if c.ID == "" || c.Name == "" || ids[c.ID] {
				t.Fatalf("%s: bad or duplicate category %+v", code, c)
			}
			ids[c.ID] = true
			if len(c.Words) < 30 {
				t.Errorf("%s/%s has %d words, want at least 30", code, c.ID, len(c.Words))
			}
			for _, w := range c.Words {
				if !isSecret(w, script) {
					t.Errorf("%s/%s: %q must be one or more plain words in the language's script", code, c.ID, w)
				}
				if seen[w] {
					t.Errorf("%s: %q appears more than once", code, w)
				}
				seen[w] = true
				total++
			}
		}
		// Each language has its own set (Hebrew keeps its Israeli categories),
		// but every one is deep enough to play for long.
		if total < 1000 {
			t.Errorf("%s: %d words, want at least 1000", code, total)
		}
	}
}

// Category names key the bot hints and reach players as the public category,
// so no two languages may share one.
func TestCategoryNamesAreUniqueAcrossLanguages(t *testing.T) {
	names := map[string]bool{}
	for _, c := range allCategories() {
		if names[c.Name] {
			t.Errorf("category name %q is used twice", c.Name)
		}
		names[c.Name] = true
	}
}

// Every language offers the free categories and the same reaction ids, and
// has what its staging bots need.
func TestLanguagesAgree(t *testing.T) {
	he := mustLanguage(t, DefaultLanguage)
	for _, code := range Languages() {
		l := mustLanguage(t, code)
		for _, free := range []string{"food", "places", "film_tv"} {
			if !l.ValidIDs([]string{free}) {
				t.Errorf("%s lacks the free category %s", code, free)
			}
		}
		if len(l.Reactions) != len(he.Reactions) {
			t.Errorf("%s has %d reactions, want %d", code, len(l.Reactions), len(he.Reactions))
		}
		for i := range min(len(l.Reactions), len(he.Reactions)) {
			if l.Reactions[i].ID != he.Reactions[i].ID || l.Reactions[i].Text == "" {
				t.Errorf("%s reaction %d is %+v, want id %s", code, i, l.Reactions[i], he.Reactions[i].ID)
			}
		}
		b := l.Bots
		if b.Prefix == "" || len(b.Names["f"]) < 8 || len(b.Names["m"]) < 8 || len(b.FallbackHints) == 0 || b.UnknownGuess == "" {
			t.Errorf("%s: incomplete bots section %+v", code, b)
		}
	}
	if _, ok := For(""); !ok {
		t.Error("an empty language is not the default")
	}
	if _, ok := For("xx"); ok {
		t.Error("an unknown language was found")
	}
}

func TestGuessAliasesBelongToKnownSecrets(t *testing.T) {
	known := map[string]bool{}
	for _, c := range allCategories() {
		for _, word := range c.Words {
			known[word] = true
		}
	}
	for word, aliases := range tables.aliases {
		if !known[word] {
			t.Errorf("aliases exist for unknown secret %q", word)
		}
		if len(aliases) == 0 {
			t.Errorf("%q has an empty alias list", word)
		}
		seen := map[string]bool{}
		for _, alias := range aliases {
			if strings.TrimSpace(alias) == "" {
				t.Errorf("%q has a blank alias", word)
			}
			if seen[alias] {
				t.Errorf("%q repeats alias %q", word, alias)
			}
			seen[alias] = true
		}
	}
}

func TestValidIDs(t *testing.T) {
	he := mustLanguage(t, "he")
	switch {
	case !he.ValidIDs([]string{"food"}), !he.ValidIDs([]string{"food", "gaming"}):
		t.Fatal("known ids rejected")
	case he.ValidIDs(nil), he.ValidIDs([]string{"food", "cars"}):
		t.Fatal("empty or unknown ids accepted")
	case !KnownCategory("gaming"), KnownCategory("cars"):
		t.Fatal("KnownCategory")
	}
}

func TestPickUsesOnlyTheChosenCategories(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 2))
	seen := map[string]bool{}
	for range 500 {
		name, word, ok := Pick("he", []string{"food", "home"}, rng)
		if !ok || (name != "אוכל ושתייה" && name != "בבית") {
			t.Fatalf("Pick = %q %q %v", name, word, ok)
		}
		if c, _ := CategoryNamed(name); !slices.Contains(c.Words, word) {
			t.Fatalf("%q is not in %s", word, name)
		}
		seen[name+"\x00"+word] = true
	}
	if len(seen) < 80 {
		t.Fatalf("only %d of 100 category-word pairs picked in 500 draws", len(seen))
	}
	if _, _, ok := Pick("he", []string{"cars"}, rng); ok {
		t.Fatal("unknown category picked a word")
	}
	if _, _, ok := Pick("xx", []string{"food"}, rng); ok {
		t.Fatal("unknown language picked a word")
	}
}

func TestReactions(t *testing.T) {
	ids, texts := map[string]bool{}, map[string]bool{}
	reactions := mustLanguage(t, "he").Reactions
	for _, r := range reactions {
		if r.ID == "" || r.Text == "" || ids[r.ID] || texts[r.Text] {
			t.Fatalf("bad or duplicate reaction %+v", r)
		}
		ids[r.ID], texts[r.Text] = true, true
	}
	if len(reactions) != 10 {
		t.Fatalf("%d reactions, want 6 emoji and 4 messages", len(reactions))
	}
	if !ValidReaction("good_hint") || ValidReaction("רמז טוב!") || ValidReaction("") {
		t.Fatal("reactions are accepted by id only")
	}
	if p := Policy(); p.HintInappropriate("anything") || !p.ValidReaction("laugh") {
		t.Fatal("the MVP policy blocks no hint and accepts approved reactions")
	} else if !slices.Contains(p.GuessAliases("פקמן"), "פאקמן") {
		t.Fatal("the content policy did not expose configured guess aliases")
	}
}
