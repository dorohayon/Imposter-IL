package api

import (
	"fmt"
	"slices"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/content"
	"github.com/dorohayon/Imposter-IL/server/internal/game"
	"github.com/dorohayon/Imposter-IL/server/internal/matchmaking"
)

var stagingBotProfiles = []struct {
	name, avatar string
}{
	{"בוט בלש", "avatar-m04-detective-hat"},
	{"בוט רמז", "avatar-f01-notebook"},
	{"בוט חשוד", "avatar-m02-binoculars"},
}

const (
	// How long a bot appears to spend writing a hint, and deciding a vote.
	stagingBotWriteSeconds = 10
	stagingBotVoteSeconds  = 4
	// One hint in stagingBotSilence gets no reaction from a given bot, so the
	// board is not identical every turn.
	stagingBotSilence = 3
)

// botStillThinking reports whether the bot has not finished its pause yet,
// starting one if it has none pending.
func (s *Server) botStillThinking(bot *session, now time.Time, d time.Duration) bool {
	if bot.botActAt.IsZero() {
		bot.botActAt = now.Add(d)
	}
	if now.Before(bot.botActAt) {
		return true
	}
	bot.botActAt = time.Time{}
	return false
}

var stagingBotHints = []string{
	"מיוחד", "מוכר", "צבעוני", "נפוץ", "מעניין", "גדול", "קטן",
	"מהיר", "ישן", "חדש", "עגול", "חזק", "נדיר", "שימושי",
}

// rebalanceStagingBots fills a forming online match to four players, then
// yields seats as real players arrive. No bots remain without a real player.
// The server lock is held by every caller.
func (s *Server) rebalanceStagingBots(entry *roomEntry, categories []string, now time.Time) {
	if s.stagingBots == 0 || !s.searching(entry) {
		return
	}
	members := entry.room.View().Members
	var bots []*session
	humans := 0
	for _, member := range members {
		if sess := s.players[member.ID]; sess != nil && sess.bot {
			bots = append(bots, sess)
		} else {
			humans++
		}
	}
	desired := min(s.stagingBots, max(matchmaking.MinPlayers-humans, 0))
	if humans == 0 {
		desired = 0
	}
	for len(bots) > desired {
		bot := bots[len(bots)-1]
		bots = bots[:len(bots)-1]
		_ = entry.room.Leave(bot.playerID, now)
		bot.roomID = ""
		delete(s.players, bot.playerID)
	}
	for len(bots) < desired {
		profile := stagingBotProfiles[len(bots)%len(stagingBotProfiles)]
		s.botSequence++
		id := fmt.Sprintf("p_bot_%d", s.botSequence)
		bot := &session{
			playerID:         id,
			nickname:         profile.name,
			avatarID:         profile.avatar,
			roomID:           entry.id,
			bot:              true,
			connected:        true,
			lastSeen:         now,
			searchCategories: slices.Clone(categories),
			searchStarted:    now,
		}
		if err := entry.room.Join(id, now); err != nil {
			break
		}
		s.players[id] = bot
		bots = append(bots, bot)
	}
}

// removeGameBotsWithoutHumans ends an abandoned bot-only game immediately.
func (s *Server) removeGameBotsWithoutHumans(entry *roomEntry, now time.Time) {
	members := entry.room.View().Members
	for _, member := range members {
		if sess := s.players[member.ID]; sess != nil && !sess.bot {
			return
		}
	}
	for _, member := range members {
		bot := s.players[member.ID]
		if bot == nil || !bot.bot {
			continue
		}
		_ = entry.room.Leave(bot.playerID, now)
		bot.roomID = ""
		bot.leaveGame()
		delete(s.players, bot.playerID)
	}
}

// botReact reacts to the newest hint, after a pause, so one real player can
// see reactions arrive without a second person to send them. Reporting whether
// it reacted, for the caller's publish.
func (s *Server) botReact(entry *roomEntry, bot *session, view game.View, now time.Time) bool {
	hints := len(view.Hints)
	if hints < bot.botReacted {
		bot.botReacted = 0 // a second game in the same room
	}
	last := hints - 1
	// Nobody reacts to their own hint, and a missing one has nothing to react
	// to. One chance per hint, taken or not.
	if hints == 0 || bot.botReacted == hints ||
		view.Hints[last].Missing || view.Hints[last].PlayerID == bot.playerID {
		return false
	}
	if bot.botReactAt.IsZero() {
		if s.rng.IntN(stagingBotSilence) == 0 {
			bot.botReacted = hints
			return false
		}
		// Reading the hint, then reaching for a reaction. Spread out, so the
		// bots do not all answer in the same frame.
		bot.botReactAt = now.Add(time.Duration(600+s.rng.IntN(2600)) * time.Millisecond)
		return false
	}
	if now.Before(bot.botReactAt) {
		return false
	}
	bot.botReactAt = time.Time{}
	bot.botReacted = hints
	reaction := content.Reactions[s.rng.IntN(len(content.Reactions))]
	return entry.room.WithGame(now, func(g *game.Game) error {
		return g.React(bot.playerID, last, reaction.ID, now)
	}) == nil
}

// runStagingBots advances only bot turns. It is intentionally in-process:
// Cloud Run can still scale to zero, and the first real WebSocket request
// wakes the instance and creates its companions.
func (s *Server) runStagingBots() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.stagingBots == 0 {
		return
	}
	for _, entry := range slices.Clone(s.publicRooms) {
		s.removeGameBotsWithoutHumans(entry, s.now())
		if entry.room.Game() != nil {
			s.runStagingBotsInGame(entry, s.now())
		}
	}
}

func (s *Server) runStagingBotsInGame(entry *roomEntry, now time.Time) {
	g := entry.room.Game()
	if g == nil {
		return
	}
	changed := false
	for _, id := range g.PlayerIDs() {
		bot := s.players[id]
		if bot == nil || !bot.bot {
			continue
		}
		view, err := g.View(id)
		if err != nil {
			continue
		}
		var actionErr error
		reacted := s.botReact(entry, bot, view, now)
		acted := false
		switch view.Phase {
		case game.PhaseRoleReveal:
			for _, player := range view.Players {
				if player.ID == id && !player.RoleConfirmed {
					acted = true
					actionErr = entry.room.WithGame(now, func(g *game.Game) error {
						return g.ConfirmRole(id, now)
					})
				}
			}
		case game.PhaseHints:
			if view.CurrentTurn != id || view.Reconnecting {
				bot.botActAt = time.Time{}
			} else if s.botStillThinking(bot, now, stagingBotWriteSeconds*time.Second) {
				// Writing takes a human a moment. Without this the hint lands
				// in the same frame as the turn, and nobody can follow the
				// round; the other players see "כותב רמז..." meanwhile.
			} else {
				acted = true
				for range stagingBotHints {
					hint := stagingBotHints[s.botHint%uint64(len(stagingBotHints))]
					s.botHint++
					actionErr = entry.room.WithGame(now, func(g *game.Game) error {
						return g.SubmitHint(id, hint, now)
					})
					if actionErr == nil {
						break
					}
				}
			}
		case game.PhaseVoting, game.PhaseRunoffVoting:
			if view.MyVote != "" {
				bot.botActAt = time.Time{}
			} else if s.botStillThinking(bot, now, stagingBotVoteSeconds*time.Second) {
				// Deliberating, so the votes do not all land at once.
			} else if view.MyVote == "" {
				candidates := slices.DeleteFunc(slices.Clone(view.Candidates), func(candidate string) bool {
					return candidate == id
				})
				if len(candidates) > 0 {
					acted = true
					target := candidates[s.rng.IntN(len(candidates))]
					actionErr = entry.room.WithGame(now, func(g *game.Game) error {
						return g.Vote(id, target, now)
					})
				}
			}
		case game.PhaseImpostorGuess:
			if view.Role == game.RoleImpostor {
				acted = true
				actionErr = entry.room.WithGame(now, func(g *game.Game) error {
					return g.SubmitGuess(id, "לאיודע", now)
				})
			}
		}
		changed = changed || reacted || (acted && actionErr == nil)
	}
	if changed {
		s.publish(entry)
	}
}
