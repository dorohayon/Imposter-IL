package content

import (
	"math/rand/v2"
	"slices"
	"strings"
	"testing"
	"unicode"
)

func TestCategoriesAreWellFormed(t *testing.T) {
	ids, words := map[string]bool{}, map[string]string{}
	for _, c := range Categories {
		if c.ID == "" || c.Name == "" || ids[c.ID] {
			t.Fatalf("bad or duplicate category %+v", c)
		}
		ids[c.ID] = true
		if len(c.Words) != 20 {
			t.Errorf("%s has %d words, want 20", c.ID, len(c.Words))
		}
		for _, w := range c.Words {
			if w == "" || strings.ContainsFunc(w, unicode.IsSpace) {
				t.Errorf("%s: %q must be one word", c.ID, w)
			}
			if other, dup := words[w]; dup {
				t.Errorf("%q appears in %s and %s", w, other, c.ID)
			}
			words[w] = c.ID
		}
	}
	if len(Categories) != 6 {
		t.Fatalf("%d categories, want 6", len(Categories))
	}
}

func TestValidIDs(t *testing.T) {
	switch {
	case !ValidIDs([]string{"food"}), !ValidIDs([]string{"food", "objects"}):
		t.Fatal("known ids rejected")
	case ValidIDs(nil), ValidIDs([]string{"food", "cars"}):
		t.Fatal("empty or unknown ids accepted")
	}
}

func TestPickUsesOnlyTheChosenCategories(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 2))
	seen := map[string]bool{}
	for range 500 {
		name, word, ok := Pick([]string{"food", "animals"}, rng)
		if !ok || (name != "אוכל" && name != "חיות") {
			t.Fatalf("Pick = %q %q %v", name, word, ok)
		}
		if c := Categories[slices.IndexFunc(Categories, func(c Category) bool { return c.Name == name })]; !slices.Contains(c.Words, word) {
			t.Fatalf("%q is not in %s", word, name)
		}
		seen[word] = true
	}
	if len(seen) < 35 {
		t.Fatalf("only %d of 40 words picked in 500 draws", len(seen))
	}
	if _, _, ok := Pick([]string{"cars"}, rng); ok {
		t.Fatal("unknown category picked a word")
	}
}
