package content

import "testing"

func TestBlocked(t *testing.T) {
	cases := map[string]bool{
		"":         false,
		"פיל":      false,
		"כלב":      false,
		"מחשב":     false,
		"שרמוטה":   true,
		"והשרמוטה": true, // prefix letters, like the game's own word rules
		"זונה":     true,
		"הזונה":    true,
		"בןזונה":   true, // the space is dropped by normalisation
		"חרא":      true,
		"היטלר":    true,
		// A short entry matches as a whole word or with Hebrew prefix letters,
		// but not any word that merely ends the same way.
		"תחת":   true,
		"התחת":  true,
		"לתחת":  true,
		"מתחתן": false,
		"מאזין": false, // "מא" is not a run of prefix letters
		"אוזן":  false,
		// Known over-block: "מזין" is מ + a blocked stem, which no rule can
		// tell from a genuine prefixed form. Refusing one ordinary word beats
		// letting the prefixed insult through. If it matters, the fix is to
		// revisit the list, which is the owner's (docs/open-decisions.md).
		"מזין": true,
	}
	for input, want := range cases {
		if got := Blocked(input); got != want {
			t.Errorf("Blocked(%q) = %v, want %v", input, got, want)
		}
	}
}

// The policy the server is built with must actually use the list: wiring it
// back to "nothing is blocked" would pass every other test silently.
func TestPolicyUsesTheBlocklist(t *testing.T) {
	if !Policy().HintInappropriate("שרמוטה") {
		t.Fatal("game policy does not block anything")
	}
	if Policy().HintInappropriate("פיל") {
		t.Fatal("game policy blocks an ordinary word")
	}
}

func TestCommentsAndBlanksAreNotWords(t *testing.T) {
	got := parseBlocked("# comment\n\n  זונה  \n\n# another\n")
	if len(got) != 1 || got[0] != "זונה" {
		t.Fatalf("parseBlocked = %q", got)
	}
}
