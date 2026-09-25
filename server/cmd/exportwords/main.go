// Command exportwords writes the categories and secret words into the Flutter
// app as Dart source.
//
// The one-device game runs with no server, so the app needs the words on the
// device — but a second hand-written list is a list that drifts. This keeps
// server/internal/content the only place the words are decided, and
// TestDartExportMatchesTheCategories fails when the generated file falls
// behind. Run it from server/: go run ./cmd/exportwords
package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/dorohayon/Imposter-IL/server/internal/content"
)

const target = "../app/lib/local/words.g.dart"

func main() {
	if err := os.WriteFile(target, []byte(render()), 0o644); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println("wrote", target)
}

// quote escapes a word for a single-quoted Dart string. Hebrew spells ג'ירפה
// and ג'ודו with a geresh, which is an apostrophe.
func quote(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(s, `\`, `\\`), "'", `\'`)
}

func render() string {
	var b strings.Builder
	b.WriteString(`// GENERATED FILE — DO NOT EDIT.
//
// The words the one-device game draws on. Generated from
// server/internal/content by "go run ./cmd/exportwords", because a game with
// no server still needs them on the device, and a second hand-written list is
// a list that drifts. The Go test guarding this fails if the two fall out of
// step.

/// A category and the words it can produce.
class LocalCategory {
  const LocalCategory(this.id, this.name, this.words);

  final String id;
  final String name;
  final List<String> words;
}

const localCategories = <LocalCategory>[
`)
	for _, c := range content.Categories {
		fmt.Fprintf(&b, "  LocalCategory('%s', '%s', [\n", c.ID, quote(c.Name))
		for _, w := range c.Words {
			fmt.Fprintf(&b, "    '%s',\n", quote(w))
		}
		b.WriteString("  ]),\n")
	}
	b.WriteString("];\n\n")

	b.WriteString("// Alternate spellings accepted only for the impostor's final guess.\n")
	b.WriteString("const localGuessAliases = <String, List<String>>{\n")
	seen := map[string]bool{}
	for _, c := range content.Categories {
		for _, w := range c.Words {
			if seen[w] {
				continue
			}
			seen[w] = true
			aliases := content.GuessAliases(w)
			if len(aliases) == 0 {
				continue
			}
			fmt.Fprintf(&b, "  '%s': [", quote(w))
			for i, alias := range aliases {
				if i > 0 {
					b.WriteString(", ")
				}
				fmt.Fprintf(&b, "'%s'", quote(alias))
			}
			b.WriteString("],\n")
		}
	}
	b.WriteString("};\n")
	return b.String()
}
