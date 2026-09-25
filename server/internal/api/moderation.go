package api

import (
	"log/slog"
)

// Moderation for what players write (App Store 1.2, Google Play UGC).
//
// What the stores require is the minimum this does (docs/moderation.md):
// content is filtered (content.Policy), players can report and block (the
// reporter's app hides the reported player from then on), and reports are
// acted on: every report is logged under reportLogMessage with what was
// reported — the clue and the nickname — so the operator reviews it from the
// log and the email alert that watches for that message within 24 hours, and
// extends the blocklist where it missed something.
//
// There is deliberately no automatic hiding for the whole table: with no
// accounts, one person with two sessions could silence anyone.

// reportLogMessage is what the Cloud Logging alert and saved query match.
// Changing it silences the alert; deploy/setup-moderation-alerts.sh has it too.
const reportLogMessage = "player reported"

// report records one report and logs it for review. Called under s.mu.
func (s *Server) report(entry *roomEntry, by *session, reportedID string, hintIndex *int) {
	s.metrics.reports++
	if entry.reported == nil {
		entry.reported = map[string]map[string]bool{}
	}
	if entry.reported[reportedID] == nil {
		entry.reported[reportedID] = map[string]bool{}
	}
	entry.reported[reportedID][by.playerID] = true

	// What was reported, so it can be judged without anyone's help: the clue
	// (at most 25 characters) and the nickname (at most 18), both already
	// shown to everyone in the game. The client's free text is never logged:
	// the app sends none, and any client could write anything there.
	nickname := entry.profiles[reportedID].nickname
	if sess := s.players[reportedID]; sess != nil {
		nickname = sess.nickname
	}
	hint := ""
	if g := entry.room.Game(); g != nil && hintIndex != nil {
		if v, err := g.View(by.playerID); err == nil && *hintIndex >= 0 && *hintIndex < len(v.Hints) &&
			v.Hints[*hintIndex].PlayerID == reportedID {
			hint = v.Hints[*hintIndex].Text
		}
	}
	slog.Warn(reportLogMessage,
		"gameId", entry.gameID, "byPlayerId", by.playerID, "playerId", reportedID,
		"nickname", nickname, "hint", hint, "hintIndex", hintIndex,
		"reporters", len(entry.reported[reportedID]))
}
