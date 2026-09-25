package game

import (
	"encoding/json"
	"os"
	"testing"
)

func TestWordRules(t *testing.T) {
	raw, err := os.ReadFile("testdata/word_rules.json")
	if err != nil {
		t.Fatal(err)
	}
	var cases struct {
		Normalize      [][]string `json:"normalize"`
		ContainsSecret [][]any    `json:"containsSecret"`
		SameHint       [][]any    `json:"sameHint"`
		GuessMatches   [][]any    `json:"guessMatches"`
	}
	if err := json.Unmarshal(raw, &cases); err != nil {
		t.Fatal(err)
	}
	for _, c := range cases.Normalize {
		if got := normalizeWord(c[0]); got != c[1] {
			t.Errorf("normalizeWord(%q) = %q, want %q", c[0], got, c[1])
		}
	}
	for name, check := range map[string]struct {
		rows [][]any
		fn   func(a, b string) bool
	}{
		"hintContainsSecret": {cases.ContainsSecret, hintContainsSecret},
		"sameHint":           {cases.SameHint, sameHint},
		"guessMatches":       {cases.GuessMatches, func(a, b string) bool { return guessMatches(a, b) }},
	} {
		if len(check.rows) == 0 {
			t.Fatalf("no %s cases", name)
		}
		for _, c := range check.rows {
			a, b, want := c[0].(string), c[1].(string), c[2].(bool)
			if got := check.fn(a, b); got != want {
				t.Errorf("%s(%q, %q) = %v, want %v", name, a, b, got, want)
			}
		}
	}
}

func TestGuessMatchesAliases(t *testing.T) {
	aliases := []string{"פקמן", "Pac-Man"}
	for _, guess := range []string{"פאקמן", "פקמן", "Pac-Man"} {
		if !guessMatches(guess, "פאקמן", aliases...) {
			t.Errorf("%q should match פאקמן through the canonical spelling or aliases", guess)
		}
	}
	if guessMatches("טטריס", "פאקמן", aliases...) {
		t.Fatal("unrelated guess matched an alias")
	}
}
