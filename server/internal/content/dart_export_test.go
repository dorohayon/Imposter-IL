package content

import (
	"os"
	"strings"
	"testing"
)

// The one-device game plays with no server, so the words live on the device
// too — and two lists of words are two lists that drift. This is the only
// thing keeping them one list: run "go run ./cmd/exportwords" when it fails.
func TestDartExportMatchesTheCategories(t *testing.T) {
	const path = "../../../app/lib/local/words.g.dart"
	generated, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	dart := string(generated)

	for _, c := range Categories {
		name := strings.ReplaceAll(c.Name, "'", `\'`)
		if !strings.Contains(dart, "LocalCategory('"+c.ID+"', '"+name+"', [") {
			t.Errorf("category %q (%s) is missing from %s", c.Name, c.ID, path)
		}
		for _, w := range c.Words {
			// The geresh in ג'ירפה is an apostrophe, escaped in Dart source.
			escaped := strings.ReplaceAll(w, "'", `\'`)
			if !strings.Contains(dart, "    '"+escaped+"',") {
				t.Errorf("word %q is missing from %s", w, path)
			}
		}
	}

	// And nothing extra: a word deleted here must not live on there.
	words := 0
	for _, line := range strings.Split(dart, "\n") {
		if strings.HasPrefix(line, "    '") {
			words++
		}
	}
	total := 0
	for _, c := range Categories {
		total += len(c.Words)
	}
	if words != total {
		t.Errorf("%s holds %d words, the categories hold %d: run go run ./cmd/exportwords",
			path, words, total)
	}
	if strings.Count(dart, "LocalCategory(") != len(Categories)+1 { // +1 for the class
		t.Errorf("%s holds a different number of categories: run go run ./cmd/exportwords", path)
	}

	for _, c := range Categories {
		for _, word := range c.Words {
			aliases := GuessAliases(word)
			if len(aliases) == 0 {
				continue
			}
			escapedWord := strings.ReplaceAll(word, "'", `\'`)
			if !strings.Contains(dart, "  '"+escapedWord+"': [") {
				t.Errorf("aliases for %q are missing from %s", word, path)
			}
			for _, alias := range aliases {
				escapedAlias := strings.ReplaceAll(alias, "'", `\'`)
				if !strings.Contains(dart, "'"+escapedAlias+"'") {
					t.Errorf("alias %q for %q is missing from %s", alias, word, path)
				}
			}
		}
	}
}
