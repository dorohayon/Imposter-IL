// Package content holds the approved categories and secret words.
package content

import (
	"math/rand/v2"
	"slices"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

type Category struct {
	ID    string
	Name  string
	Words []string
}

// Categories is the first approved batch (docs/decisions.md).
var Categories = []Category{
	{"food", "אוכל", []string{"פיצה", "פלאפל", "שווארמה", "המבורגר", "סושי", "פסטה", "חומוס", "שניצל", "פנקייק", "קוסקוס", "מרק", "גלידה", "שוקולד", "אבטיח", "בננה", "תות", "פופקורן", "סלט", "בורקס", "עוגה"}},
	{"animals", "חיות", []string{"כלב", "חתול", "אריה", "נמר", "פיל", "ג'ירפה", "קוף", "דולפין", "כריש", "תנין", "זברה", "פינגווין", "סוס", "תרנגול", "כבשה", "עז", "שועל", "דוב", "צב", "תוכי"}},
	{"sports", "ספורט", []string{"כדורגל", "כדורסל", "כדורעף", "טניס", "שחייה", "ריצה", "אגרוף", "ג'ודו", "גלישה", "סקי", "סנוקר", "באולינג", "התעמלות", "קראטה", "היאבקות", "פינגפונג", "הוקי", "פוטבול", "בייסבול", "רכיבה"}},
	{"professions", "מקצועות", []string{"רופא", "מורה", "שוטר", "כבאי", "טבח", "נהג", "טייס", "עיתונאי", "צלם", "מהנדס", "נגר", "חשמלאי", "אדריכל", "חקלאי", "רוקח", "זמר", "וטרינר", "בלש", "מדען", "שף"}},
	{"places", "מקומות", []string{"חוף", "מדבר", "יער", "מערה", "שוק", "פארק", "קניון", "מוזיאון", "ספרייה", "מסעדה", "אצטדיון", "טירה", "ארמון", "נמל", "אוניברסיטה", "מלון", "בריכה", "קולנוע", "כלא", "שדה"}},
	{"objects", "חפצים", []string{"מטרייה", "מפתח", "שעון", "טלפון", "מצלמה", "משקפיים", "תיק", "כרית", "כיסא", "שולחן", "מנורה", "מחשב", "אוזניות", "מראה", "בקבוק", "מגבת", "פנס", "סולם", "מזוודה", "שלט"}},
}

// ValidIDs reports whether ids is non-empty and names only known categories.
func ValidIDs(ids []string) bool {
	if len(ids) == 0 {
		return false
	}
	for _, id := range ids {
		if !slices.ContainsFunc(Categories, func(c Category) bool { return c.ID == id }) {
			return false
		}
	}
	return true
}

// Pick chooses a random word from the given categories, each word equally
// likely, and returns it with its category name.
func Pick(ids []string, rng *rand.Rand) (categoryName, word string, ok bool) {
	var pool []Category
	total := 0
	for _, c := range Categories {
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

type Reaction struct {
	ID   string // stable id sent as reactionId
	Text string // emoji or structured message shown in the app
}

// Reactions is the approved list (docs/decisions.md): six emoji and four
// structured messages.
var Reactions = []Reaction{
	{"laugh", "😂"},
	{"thinking", "🤔"},
	{"eyes", "👀"},
	{"surprised", "😮"},
	{"applause", "👏"},
	{"eye_roll", "🙄"},
	{"good_hint", "רמז טוב!"},
	{"suspicious", "זה מחשיד"},
	{"not_convinced", "לא השתכנעתי"},
	{"what_connection", "מה הקשר?"},
}

// Policy is the game policy: the approved reactions and the blocked-word list
// the app stores require for user-generated content (blocklist.go).
func Policy() game.Policy {
	return game.Policy{
		HintInappropriate: Blocked,
		ValidReaction:     ValidReaction,
	}
}

// ValidReaction reports whether id is an approved reaction id.
func ValidReaction(id string) bool {
	return slices.ContainsFunc(Reactions, func(r Reaction) bool { return r.ID == id })
}

// BotHints are plausible one-word hints per category, for the staging bots.
//
// They are not a game rule and no player ever sees this list: it exists so
// that one real player at a table of bots reads hints that belong to the round
// instead of the same handful of adjectives every game. A bot that draws from
// the category — which is all the impostor can do anyway — looks like someone
// thinking.
var botHints = map[string][]string{
	"אוכל": {"טעים", "חם", "מתוק", "מלוח", "ארוחה", "מסעדה", "רעב", "קינוח",
		"בישול", "מנה", "חגיגי", "ילדים", "שישי", "פופולרי"},
	"חיות": {"פרווה", "יער", "בר", "מסוכן", "חמוד", "זנב", "טורף", "אפריקה",
		"מים", "שקט", "מהיר", "כלוב", "ביות", "צעיר"},
	"ספורט": {"כדור", "אולם", "אליפות", "אימון", "נעליים", "קבוצה", "מדליה",
		"מגרש", "זיעה", "שופט", "תחרות", "מהירות", "ריכוז", "אולימפיאדה"},
	"מקצועות": {"עבודה", "מדים", "שירות", "אחריות", "משרד", "תעודה", "שכר",
		"אנשים", "ידיים", "ניסיון", "שליחות", "בוקר", "לימודים", "מקצוע"},
	"מקומות": {"ביקור", "נסיעה", "כרטיס", "רחב", "חופשה", "קיץ", "כניסה",
		"בניין", "טיול", "נוף", "המולה", "שקט", "אנשים", "מקום"},
	"חפצים": {"שימושי", "בית", "כיס", "פלסטיק", "קטן", "יומיומי", "מתנה",
		"עץ", "חשמל", "תיק", "שולחן", "נשכח", "חפץ", "כבד"},
}

// BotHints returns the pool for a category name, or nil if there is none.
func BotHints(category string) []string { return botHints[category] }
