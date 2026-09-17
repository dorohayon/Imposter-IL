package content

import "testing"

func TestBlocked(t *testing.T) {
	blocked := []string{
		// Plain entries, and the forms people actually type.
		"זונה", "הזונה", "שרמוטה", "והשרמוטה", "חרא", "מניאק",
		"בן זונה", "בן-זונה", "בןזונה", // spaces and punctuation are stripped
		"כוסאמא", "כוס אמא",
		"היטלר", "נאצי", "ניגר",
		"מוות לערבים", "אני אהרוג אותך",
		"fuck", "FUCK", "f.u.c.k", "Motherfucker",
		"nigger", "retard", "kill yourself", "killyourself",
		"פדופיל", "סקס", "אונס",
	}
	for _, word := range blocked {
		if !Blocked(word) {
			t.Errorf("Blocked(%q) = false, want true", word)
		}
	}

	// The other half of the job: ordinary words must get through. Blocking a
	// legitimate hint is a bug too, and a more likely one — every entry here
	// was refused by an earlier version of the matching rules.
	allowed := []string{
		// Ordinary words that the approved list deliberately leaves out.
		"כוס", "תחת", "יהודי", "ערבי", "הומו", "לסבית", "מוסלמי", "נוצרי",
		// Hebrew words a prefix rule once swallowed.
		"מזין", "מאזין", "אוזן", "אפסים", "זבלן",
		// English words a substring rule once swallowed.
		"cocktail", "peacock", "cockpit", "grape", "scrape", "dickens",
		"basement", "assassin", "shiitake", "classic", "analysis",
		// And the game's own content.
		"פיצה", "כלב", "מחשב", "אריה", "שוקולד", "ריצה", "מורה", "מטרייה",
	}
	for _, word := range allowed {
		if Blocked(word) {
			t.Errorf("Blocked(%q) = true, want false", word)
		}
	}
}

// Known over-blocks, recorded rather than hidden. Hebrew prefix letters are
// allowed in front of a four-letter entry so that הזונה is caught, and that
// same rule refuses a few ordinary words built the same way. Tightening it
// further would let the forms that matter through, so the trade is
// deliberate; revisit it if a real hint is ever refused.
func TestKnownOverBlocks(t *testing.T) {
	for _, word := range []string{"מסתום"} {
		if !Blocked(word) {
			t.Errorf("%q is no longer over-blocked — tighten this test", word)
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
