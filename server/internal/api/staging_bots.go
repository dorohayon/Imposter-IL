package api

import (
	"fmt"
	"slices"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/content"
	"github.com/dorohayon/Imposter-IL/server/internal/game"
	"github.com/dorohayon/Imposter-IL/server/internal/matchmaking"
)

// Staging bots are named "בוט" and an ordinary Hebrew first name. The prefix
// is not decoration: a player has to be able to tell at a glance who at the
// table is not a person. The name behind it is what makes the table readable —
// "בוט חשוד" and "בוט רמז" read as roles rather than as players, and a round
// of them was hard to follow.
//
// Kept in two lists so that a bot's avatar matches the name it is given.
var stagingBotNames = map[string][]string{
	"f": {"נועה", "שירה", "יעל", "מאיה", "תמר", "אביגיל", "הילה", "רוני",
		"ליאור", "דנה", "אור", "טליה", "עדי", "מיכל", "שני", "אלה"},
	"m": {"איתי", "נועם", "יונתן", "דניאל", "אורי", "עידו", "אלון", "גיא",
		"עומר", "יואב", "אריאל", "תומר", "רועי", "אסף", "ניר", "עמית"},
}

var stagingBotAvatars = map[string][]string{
	"f": {"avatar-f01-notebook", "avatar-f02-camera", "avatar-f03-headphones",
		"avatar-f04-map", "avatar-f05-fingerprint-kit", "avatar-f06-laptop"},
	"m": {"avatar-m01-flashlight", "avatar-m02-binoculars", "avatar-m03-evidence-bag",
		"avatar-m04-detective-hat", "avatar-m05-badge", "avatar-m06-magnifying-glass"},
}

// botProfile picks a name and a matching avatar that nobody at this table is
// already using. Two bots called בוט נועה would be worse than the roles they
// replaced.
func (s *Server) botProfile(taken []*session) (nickname, avatar string) {
	used := func(field func(*session) string, value string) bool {
		return slices.ContainsFunc(taken, func(other *session) bool { return field(other) == value })
	}
	for attempt := 0; ; attempt++ {
		gender := "f"
		if s.rng.IntN(2) == 0 {
			gender = "m"
		}
		names, avatars := stagingBotNames[gender], stagingBotAvatars[gender]
		nickname = "בוט " + names[s.rng.IntN(len(names))]
		avatar = avatars[s.rng.IntN(len(avatars))]
		free := !used(func(b *session) string { return b.nickname }, nickname) &&
			!used(func(b *session) string { return b.avatarID }, avatar)
		// The lists are far longer than a table, so this lands almost at once;
		// the bound is only so that a shrunken list cannot spin here forever.
		if free || attempt == 50 {
			return nickname, avatar
		}
	}
}

const (
	// How long staging bots take to join a search, spread at random within.
	stagingBotJoinWindow = 10 * time.Second
	// How long a bot appears to spend writing a hint, and deciding a vote.
	stagingBotWriteSeconds = 10
	stagingBotVoteSeconds  = 4
	// One hint in stagingBotSilence gets no reaction from a given bot, so the
	// board is not identical every turn.
	stagingBotSilence = 3
	// How sharply a bot acts on how the round reads. Low enough to have an
	// opinion, high enough to be wrong often, which is most of what makes a
	// vote look like a person's.
	botVoteTemperature = 0.6
)

// botWriteTime is how long this bot appears to spend writing. Varying it is
// the difference between players thinking and a machine answering on a timer.
func (s *Server) botWriteTime() time.Duration {
	spread := stagingBotWriteSeconds * time.Second / 2
	return stagingBotWriteSeconds*time.Second - spread + time.Duration(s.rng.Int64N(int64(2*spread)))
}

// botVote picks who this bot votes for, from the board and nothing else.
//
// There is one reading of the round for every bot at the table, citizen and
// impostor alike, and it is built from what anyone watching could see: the
// category, who said what, in what order. It is not given the secret word even
// when the bot holding it is a citizen who knows it.
//
// Giving a citizen bot the word would be truer to what a citizen knows, and it
// is what this did before. The trouble is that the only thing it could judge a
// hint against was a curated pool, so a hint nobody curated — which is every
// hint a person writes — could never be judged at all, and the one human at
// the table was the one player the bots could never form an opinion about.
// Reading the round instead means a hint that does not fit is a hint that does
// not fit, whoever wrote it.
func (s *Server) botVote(view game.View, candidates []string) string {
	board := make([]content.BoardHint, 0, len(view.Hints))
	for _, h := range view.Hints {
		if !h.Missing {
			board = append(board, content.BoardHint{PlayerID: h.PlayerID, Text: h.Text})
		}
	}
	odds := content.VoteOdds(content.Suspicion(view.Category, board), candidates, botVoteTemperature)
	pick := s.rng.Float64()
	for i, chance := range odds {
		if pick < chance {
			return candidates[i]
		}
		pick -= chance
	}
	return candidates[len(candidates)-1]
}

// botGuess is the word a caught impostor names. Naming a word from the
// category is what a person does in that seat; it was the literal string
// "לאיודע", which is the most watched moment of the round spent on a shrug.
// Uniform over the category on purpose — reasoning towards the real word from
// the hints would make a bot better at this than the player it is playing
// against.
func (s *Server) botGuess(category string) string {
	for _, c := range content.Categories {
		if c.Name == category && len(c.Words) > 0 {
			return c.Words[s.rng.IntN(len(c.Words))]
		}
	}
	return "לאיודע"
}

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

// The last resort, for a category the dataset does not cover.
var stagingBotHints = []string{
	"מיוחד", "מוכר", "צבעוני", "נפוץ", "מעניין", "גדול", "קטן",
	"מהיר", "ישן", "חדש", "עגול", "חזק", "נדיר", "שימושי",
}

// botHintPool is what this bot has to work with, in the order it should try.
//
// The two roles read different things, and that is the point. A citizen bot is
// handed the word by the game and draws from that word's curated pool. An
// impostor's View carries no secret word at all, so it can only do what a
// human impostor does: look at the category and at what has already been said.
// Nothing here has to be trusted to keep them apart — with no word, the
// citizen pool cannot be reached.
func botHintPool(view game.View) []string {
	said := make([]string, 0, len(view.Hints))
	for _, h := range view.Hints {
		if !h.Missing {
			said = append(said, h.Text)
		}
	}
	// The broad pool trails the word's own, because a match runs several
	// rounds now and six curated hints shared between the citizens run out by
	// the third one. Better a broad hint than a turn nobody answers.
	pool := append(content.CitizenHints(view.SecretWord), content.ImpostorHints(view.Category, said)...)
	if len(pool) > 0 {
		return pool
	}
	return stagingBotHints
}

// stagingBotsDesired is how many bots should sit in a forming match. One human
// may get the full staging roster so the search screen can be tried; once more
// people arrive, bots yield down to the minimum needed to start.
func stagingBotsDesired(stagingBots, humans int) int {
	if humans == 0 || stagingBots == 0 {
		return 0
	}
	capacity := matchmaking.MaxPlayers - humans
	desired := min(stagingBots, capacity)
	if humans >= 2 {
		desired = min(desired, max(matchmaking.MinPlayers-humans, 0))
	}
	return desired
}

// rebalanceStagingBots fills a forming online match, then yields seats as real
// players arrive. Bots join one at a time on a random schedule within ten
// seconds so the search screen does not populate in a single frame. No bots
// remain without a real player. The server lock is held by every caller.
func (s *Server) rebalanceStagingBots(entry *roomEntry, categories []string, now time.Time) bool {
	if s.stagingBots == 0 || !s.searching(entry) {
		entry.stagingBotJoinAt = nil
		return false
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
	desired := stagingBotsDesired(s.stagingBots, humans)
	if humans == 0 {
		desired = 0
		entry.stagingBotJoinAt = nil
	}
	changed := false
	for len(bots) > desired {
		bot := bots[len(bots)-1]
		bots = bots[:len(bots)-1]
		_ = entry.room.Leave(bot.playerID, now)
		bot.roomID = ""
		delete(s.players, bot.playerID)
		changed = true
	}
	if len(bots)+len(entry.stagingBotJoinAt) > desired {
		entry.stagingBotJoinAt = entry.stagingBotJoinAt[:max(desired-len(bots), 0)]
	}
	need := desired - len(bots) - len(entry.stagingBotJoinAt)
	for range need {
		offset := time.Duration(s.rng.Int64N(int64(stagingBotJoinWindow) + 1))
		entry.stagingBotJoinAt = append(entry.stagingBotJoinAt, now.Add(offset))
	}
	slices.SortFunc(entry.stagingBotJoinAt, func(a, b time.Time) int {
		return a.Compare(b)
	})
	for len(entry.stagingBotJoinAt) > 0 && !entry.stagingBotJoinAt[0].After(now) {
		entry.stagingBotJoinAt = entry.stagingBotJoinAt[1:]
		if len(bots) >= desired {
			continue
		}
		nickname, avatar := s.botProfile(bots)
		s.botSequence++
		id := fmt.Sprintf("p_bot_%d", s.botSequence)
		bot := &session{
			playerID:         id,
			nickname:         nickname,
			avatarID:         avatar,
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
		changed = true
	}
	return changed
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

// botStillPlaying reports whether this bot is still in the round rather than
// watching it.
func botStillPlaying(view game.View, id string) bool {
	for _, p := range view.Players {
		if p.ID == id {
			return p.Status == game.StatusActive
		}
	}
	return false
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
	// Runs on the reaper's goroutine: an unrecovered panic here ends the process.
	defer s.recoverRoom(nil, "bots")
	if s.stagingBots == 0 {
		return
	}
	now := s.now()
	for _, entry := range slices.Clone(s.publicRooms) {
		if s.searching(entry) {
			if s.rebalanceStagingBots(entry, s.sharedCategories(entry), now) {
				s.lobbyChanged(entry, now)
				s.publish(entry)
			}
		}
	}
	for _, entry := range slices.Clone(s.publicRooms) {
		s.removeGameBotsWithoutHumans(entry, s.now())
		g := entry.room.Game()
		if g == nil {
			continue
		}
		s.runStagingBotsInGame(entry, s.now())
		// A match a bot ended — by voting the last citizen out, by guessing,
		// or by nobody voting twice — publishes and stops there. An ended game
		// schedules no timer, so without this the room would sit finished and
		// still full until a player happened to do something, and its bots
		// would sit in it.
		if entry.room.Game().Phase() == game.PhaseEnded {
			s.tickRoom(entry)
		}
	}
	// Last, because the loop above is one of the things that drops rooms.
	//
	// A bot exists only while its room does. Rooms are dropped by several paths
	// — a finished match settling, a lobby emptying, a panic taking one down —
	// and each lets its bots go by walking the members it has at that moment. A
	// bot that was not among them, for whatever reason, would sit in s.players
	// for the life of the process. This is the invariant itself, rather than
	// one more place that has to remember.
	for id, sess := range s.players {
		if sess.bot && s.roomsByID[sess.roomID] == nil {
			sess.leaveGame()
			delete(s.players, id)
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
		// A bot the table voted out watches like anyone else: it still reacts,
		// and it takes no turn and casts no vote.
		reacted := s.botReact(entry, bot, view, now)
		acted := false
		if view.Phase == game.PhaseEliminationReveal {
			for _, player := range view.Players {
				if player.ID != id || player.RoleConfirmed {
					continue
				}
				if player.Status != game.StatusActive && player.Status != game.StatusEliminated {
					continue
				}
				acted = true
				actionErr = entry.room.WithGame(now, func(g *game.Game) error {
					return g.ContinueAfterElimination(id, now)
				})
			}
		}
		if !botStillPlaying(view, id) {
			changed = changed || reacted || (acted && actionErr == nil)
			continue
		}
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
			} else if s.botStillThinking(bot, now, s.botWriteTime()) {
				// Writing takes a human a moment. Without this the hint lands
				// in the same frame as the turn, and nobody can follow the
				// round; the other players see "כותב רמז..." meanwhile.
			} else {
				acted = true
				pool := botHintPool(view)
				// Best first for an impostor, so start there and walk on when
				// the engine refuses one; a citizen's pool has no order worth
				// keeping, so start somewhere different each time.
				start := uint64(0)
				if view.SecretWord != "" {
					start = s.botHint
				}
				for i := range pool {
					hint := pool[(start+uint64(i))%uint64(len(pool))]
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
					target := s.botVote(view, candidates)
					actionErr = entry.room.WithGame(now, func(g *game.Game) error {
						return g.Vote(id, target, now)
					})
				}
			}
		case game.PhaseImpostorGuess:
			if view.Role == game.RoleImpostor {
				acted = true
				guess := s.botGuess(view.Category)
				actionErr = entry.room.WithGame(now, func(g *game.Game) error {
					return g.SubmitGuess(id, guess, now)
				})
			}
		}
		changed = changed || reacted || (acted && actionErr == nil)
	}
	if changed {
		s.publish(entry)
	}
}
