package content

import (
	"math/rand/v2"
	"slices"
	"strings"
	"testing"
)

func isHebrewSingleToken(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		switch {
		case r == '\'' || r == '"':
			// Common keyboard forms used in words such as צ'אט and בקו"ם.
		case r >= '\u0590' && r <= '\u05FF' && r != '\u05BE':
			// Hebrew letters, marks, geresh and gershayim. Hebrew maqaf is
			// intentionally excluded: playable secrets are one plain token.
		default:
			return false
		}
	}
	return true
}

func TestCategoriesAreWellFormed(t *testing.T) {
	ids := map[string]bool{}
	for _, c := range Categories {
		if c.ID == "" || c.Name == "" || ids[c.ID] {
			t.Fatalf("bad or duplicate category %+v", c)
		}
		ids[c.ID] = true
		if len(c.Words) != 50 {
			t.Errorf("%s has %d words, want 50", c.ID, len(c.Words))
		}
		seen := map[string]bool{}
		for _, w := range c.Words {
			if w == "" || strings.TrimSpace(w) != w {
				t.Errorf("%s: %q must be non-empty without surrounding whitespace", c.ID, w)
			}
			if !isHebrewSingleToken(w) {
				t.Errorf("%s: %q must be one Hebrew word with no Latin letters, spaces or hyphens", c.ID, w)
			}
			if seen[w] {
				t.Errorf("%s: %q appears twice in the same category", c.ID, w)
			}
			seen[w] = true
		}
	}
	if len(Categories) != 18 {
		t.Fatalf("%d categories, want 18", len(Categories))
	}
}

func TestValidIDs(t *testing.T) {
	switch {
	case !ValidIDs([]string{"food"}), !ValidIDs([]string{"food", "gaming"}):
		t.Fatal("known ids rejected")
	case ValidIDs(nil), ValidIDs([]string{"food", "cars"}):
		t.Fatal("empty or unknown ids accepted")
	}
}

func TestPickUsesOnlyTheChosenCategories(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 2))
	seen := map[string]bool{}
	for range 500 {
		name, word, ok := Pick([]string{"food", "home"}, rng)
		if !ok || (name != "אוכל ושתייה" && name != "בבית") {
			t.Fatalf("Pick = %q %q %v", name, word, ok)
		}
		if c := Categories[slices.IndexFunc(Categories, func(c Category) bool { return c.Name == name })]; !slices.Contains(c.Words, word) {
			t.Fatalf("%q is not in %s", word, name)
		}
		seen[name+"\x00"+word] = true
	}
	if len(seen) < 80 {
		t.Fatalf("only %d of 100 category-word pairs picked in 500 draws", len(seen))
	}
	if _, _, ok := Pick([]string{"cars"}, rng); ok {
		t.Fatal("unknown category picked a word")
	}
}

func TestReactions(t *testing.T) {
	ids, texts := map[string]bool{}, map[string]bool{}
	for _, r := range Reactions {
		if r.ID == "" || r.Text == "" || ids[r.ID] || texts[r.Text] {
			t.Fatalf("bad or duplicate reaction %+v", r)
		}
		ids[r.ID], texts[r.Text] = true, true
	}
	if len(Reactions) != 10 {
		t.Fatalf("%d reactions, want 6 emoji and 4 messages", len(Reactions))
	}
	if !ValidReaction("good_hint") || ValidReaction("רמז טוב!") || ValidReaction("") {
		t.Fatal("reactions are accepted by id only")
	}
	if p := Policy(); p.HintInappropriate("anything") || !p.ValidReaction("laugh") {
		t.Fatal("the MVP policy blocks no hint and accepts approved reactions")
	}
}
