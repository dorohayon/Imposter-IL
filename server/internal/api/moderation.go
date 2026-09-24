package api

import (
	"log/slog"
)

// Moderation for what players write (App Store 1.2, Google Play UGC).
//
// There are no accounts, so there is no one to ban beyond the game at hand.
// What the stores require is that reports are acted on, and this does it in
// two ways (docs/moderation.md):
//
//   - Every report is logged under reportLogMessage with what was reported —
//     the clue and the nickname — so the operator reviews it from the log and
//     the email alert that watches for that message, and extends the
//     blocklist where it missed something.
//   - Once hideAfterReports different players in a game have reported the
//     same player, that player's clues are withheld from everyone else in
//     the game at once, not only from the reporters.

// reportLogMessage is what the Cloud Logging alert and saved query match.
// Changing it silences the alert; deploy/setup-moderation-alerts.sh has it too.
const reportLogMessage = "player reported"

// hideAfterReports is how many different players in one game must report a
// player before their clues are hidden for the whole table. One would let a
// single player silence anyone they suspect.
const hideAfterReports = 2

func (e *roomEntry) hiddenForAll(playerID string) bool {
	return len(e.reported[playerID]) >= hideAfterReports
}

// report records one report and logs it for review. It returns whether the
// player just became hidden for everyone, which is what needs publishing.
// Called under s.mu.
func (s *Server) report(entry *roomEntry, by *session, reportedID string, hintIndex *int) bool {
	s.metrics.reports++
	wasHidden := entry.hiddenForAll(reportedID)
	if entry.reported == nil {
		entry.reported = map[string]map[string]bool{}
	}
	if entry.reported[reportedID] == nil {
		entry.reported[reportedID] = map[string]bool{}
	}
	entry.reported[reportedID][by.playerID] = true
	hidden := entry.hiddenForAll(reportedID)

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
		"reporters", len(entry.reported[reportedID]), "hiddenForAll", hidden)
	return hidden && !wasHidden
}
