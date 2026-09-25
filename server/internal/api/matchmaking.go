package api

import (
	crand "crypto/rand"
	"errors"
	"slices"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/content"
	"github.com/dorohayon/Imposter-IL/server/internal/matchmaking"
	"github.com/dorohayon/Imposter-IL/server/internal/room"
)

// Online matches reuse private-room machinery: each forming match is a public
// room with no code and no host commands. While it is in the lobby its members
// are exactly the players searching in it; when its game ends every member
// leaves it, and players who choose "משחק נוסף" search in it again together.

const publicRoomCode = "000000" // never exposed or looked up

func (s *Server) matchmakingCommand(sess *session, typ string, p commandPayload, now time.Time) string {
	switch typ {
	case "matchmaking.join":
		if sess.gameID != "" || s.currentRoom(sess) != nil {
			return "already_in_activity"
		}
		return s.joinSearch(sess, nil, p.CategoryIDs, now)
	case "matchmaking.cancel":
		if entry := s.currentRoom(sess); entry != nil && s.searching(entry) {
			s.leaveSearch(sess, entry, now)
			s.sendSessionState(sess)
			s.publish(entry)
		}
		return ""
	}
	return "invalid_message"
}

// contentReady reports whether games can start at all.
func (s *Server) contentReady() bool {
	return s.pickWord != nil && s.policy.HintInappropriate != nil && s.policy.ValidReaction != nil
}

// searching reports whether entry is a public room still forming a match.
func (s *Server) searching(entry *roomEntry) bool {
	if !entry.public || entry.room.View().Status != room.StatusLobby {
		return false
	}
	// A deadline can end the game inside tickRoom before publish has settled
	// its members. Do not mistake that brief lobby state for a forming match
	// and start another game with the same players.
	g := entry.room.Game()
	return g == nil || entry.settled == g
}

// sharedCategories is what every searcher in the room selected.
func (s *Server) sharedCategories(entry *roomEntry) []string {
	var shared []string
	for i, m := range entry.room.View().Members {
		categories := s.players[m.ID].searchCategories
		if i == 0 {
			shared = slices.Clone(categories)
		} else {
			shared = matchmaking.Shared(shared, categories)
		}
	}
	return shared
}

// accepts reports whether a player with categories can search in entry.
func (s *Server) accepts(entry *roomEntry, categories []string) bool {
	members := len(entry.room.View().Members)
	if !s.searching(entry) || members >= matchmaking.MaxPlayers {
		return false
	}
	return members == 0 || len(matchmaking.Shared(s.sharedCategories(entry), categories)) > 0
}

// joinSearch puts the player in previous when it still accepts them, so
// players continuing after a game stay together even if their own category
// selections differ; otherwise in the fullest public room that shares a
// category with them; otherwise in a new one.
func (s *Server) joinSearch(sess *session, previous *roomEntry, categories []string, now time.Time) string {
	switch {
	// One choke point for both matchmaking.join and game.playAgain online.
	case s.draining:
		return "server_draining"
	case !content.ValidIDs(categories):
		return "invalid_categories"
	// Here, so "משחק נוסף" is checked too: a subscription that lapsed or a
	// purchase refunded since the last match no longer opens its categories.
	case !s.categoriesAllowed(sess, categories, now):
		return "category_locked"
	case !s.contentReady():
		return "content_unavailable"
	}
	var entry *roomEntry
	if previous != nil && s.accepts(previous, categories) {
		entry = previous
	} else {
		for _, candidate := range s.publicRooms {
			if s.accepts(candidate, categories) &&
				(entry == nil || len(candidate.room.View().Members) > len(entry.room.View().Members)) {
				entry = candidate
			}
		}
	}
	if entry == nil {
		// Online matches always use the approved default; only a private room's
		// host picks a different one.
		settings := room.Settings{MaxPlayers: matchmaking.MaxPlayers, HintSeconds: room.DefaultHintSeconds, CategoryIDs: categories}
		rm, err := room.New(publicRoomCode, sess.playerID, settings, s.policy, s.rng, now)
		if err != nil {
			return "internal_error"
		}
		entry = &roomEntry{id: "r_" + crand.Text(), room: rm, public: true}
	} else if err := entry.room.Join(sess.playerID, now); err != nil {
		return "internal_error" // accepts checked capacity and status under the lock
	}
	if !slices.Contains(s.publicRooms, entry) {
		s.publicRooms = append(s.publicRooms, entry)
	}
	s.roomsByID[entry.id] = entry
	sess.roomID, sess.searchCategories, sess.searchStarted = entry.id, categories, now
	sess.searchGoneAt = time.Time{}
	sess.leaveGame()
	if !sess.bot {
		s.rebalanceStagingBots(entry, categories, now)
	}
	s.lobbyChanged(entry, now)
	s.sendSessionState(sess)
	s.publish(entry)
	return ""
}

// leaveSearch removes a searching player; an emptied public room is dropped.
func (s *Server) leaveSearch(sess *session, entry *roomEntry, now time.Time) {
	_ = entry.room.Leave(sess.playerID, now)
	sess.roomID = ""
	if !sess.bot {
		s.rebalanceStagingBots(entry, s.sharedCategories(entry), now)
	}
	s.lobbyChanged(entry, now)
}

// lobbyChanged applies the start rules after the searchers changed.
func (s *Server) lobbyChanged(entry *roomEntry, now time.Time) {
	count := len(entry.room.View().Members)
	entry.timers.Update(count, now)
	entry.lobbyVersion++
	if count == 0 {
		s.publicRooms = slices.DeleteFunc(s.publicRooms, func(e *roomEntry) bool { return e == entry })
		delete(s.roomsByID, entry.id)
	}
}

// tickSearch applies the matchmaking deadlines of a forming match: players who
// searched two minutes with fewer than 4 found get no match, and a due start
// timer starts the game.
func (s *Server) tickSearch(entry *roomEntry, now time.Time) {
	if !s.searching(entry) {
		return
	}
	for _, m := range entry.room.View().Members {
		if sess := s.players[m.ID]; sess != nil && !sess.searchGoneAt.IsZero() && !now.Before(sess.searchGoneAt.Add(searchGrace)) {
			sess.searchGoneAt = time.Time{}
			s.leaveSearch(sess, entry, now) // away too long: the search ends for them
		}
	}
	if !s.searching(entry) {
		return
	}
	members := entry.room.View().Members
	if len(members) < matchmaking.MinPlayers {
		for _, m := range members {
			sess := s.players[m.ID]
			if sess == nil {
				continue // removed earlier in this walk, e.g. a bot rebalanced away
			}
			if now.Before(sess.searchStarted.Add(matchmaking.NoMatch)) {
				continue
			}
			s.leaveSearch(sess, entry, now)
			s.queue(sess.conn, message("matchmaking.noMatch", now, map[string]any{"categoryIds": sess.searchCategories}))
			s.sendSessionState(sess)
		}
		return
	}
	if now.Before(entry.timers.StartAt()) {
		return
	}
	// Nobody is dealt into a match while offline. A searcher who dropped may
	// have cancelled on a phone that could not reach us; starting the game
	// with them would put them in a match they could only leave with a loss.
	// They leave the search instead, and the timers restart for the rest.
	removed := false
	for _, m := range members {
		if sess := s.players[m.ID]; sess != nil && !sess.searchGoneAt.IsZero() {
			sess.searchGoneAt = time.Time{}
			s.leaveSearch(sess, entry, now)
			removed = true
		}
	}
	if removed {
		return
	}
	category, word, ok := s.pickWord(s.sharedCategories(entry), s.rng)
	if !ok {
		return
	}
	if err := entry.room.StartByServer(category, word, now); err != nil {
		if !errors.Is(err, room.ErrInGame) {
			entry.timers = matchmaking.Timers{} // cannot start; players keep searching
		}
		return
	}
	entry.timers = matchmaking.Timers{}
	entry.lobbyVersion++
	s.beginGame(entry)
}

// searchGrace is how long a searching player whose connection dropped keeps
// their place (docs/decisions.md): a blip must not cost the search.
const searchGrace = 30 * time.Second

// searchDeadline is the next matchmaking event of a forming match, or zero.
func (s *Server) searchDeadline(entry *roomEntry) time.Time {
	if !s.searching(entry) {
		return time.Time{}
	}
	members := entry.room.View().Members
	var next time.Time
	consider := func(at time.Time) {
		if !at.IsZero() && (next.IsZero() || at.Before(next)) {
			next = at
		}
	}
	for _, m := range members {
		if sess := s.players[m.ID]; sess != nil && !sess.searchGoneAt.IsZero() {
			consider(sess.searchGoneAt.Add(searchGrace))
		}
	}
	if len(members) >= matchmaking.MinPlayers {
		consider(entry.timers.StartAt())
		return next
	}
	for _, m := range members {
		sess := s.players[m.ID]
		if sess == nil {
			continue
		}
		consider(sess.searchStarted.Add(matchmaking.NoMatch))
	}
	return next
}

// settleFinishedMatch empties a public room once its game has ended: players
// stay on the result screen through their sessions, and those who choose
// "משחק נוסף" search in the room again.
func (s *Server) settleFinishedMatch(entry *roomEntry, now time.Time) {
	g := entry.room.Game()
	if !entry.public || g == nil || entry.settled == g || entry.room.View().Status != room.StatusLobby {
		return
	}
	entry.settled = g
	for _, m := range entry.room.View().Members {
		_ = entry.room.Leave(m.ID, now)
		if sess := s.players[m.ID]; sess != nil {
			sess.roomID = ""
			if sess.bot {
				sess.leaveGame()
				delete(s.players, sess.playerID)
			}
		}
	}
	s.lobbyChanged(entry, now)
}

func (s *Server) publishSearch(entry *roomEntry, now time.Time) {
	members := entry.room.View().Members
	players := []map[string]string{}
	for _, m := range members {
		sess := s.players[m.ID]
		if sess == nil {
			continue
		}
		players = append(players, map[string]string{"playerId": m.ID, "nickname": sess.nickname, "avatarId": sess.avatarID})
	}
	status := entry.timers.Status()
	shared := s.sharedCategories(entry)
	for _, m := range members {
		sess := s.players[m.ID]
		if sess == nil {
			continue
		}
		deadline := entry.timers.StartAt()
		if status == matchmaking.StatusSearching {
			deadline = sess.searchStarted.Add(matchmaking.NoMatch) // when "no match" would show
		}
		s.queue(sess.conn, message("matchmaking.state", now, map[string]any{
			"stateVersion":  entry.stateVersion,
			"status":        status,
			"categoryIds":   shared,
			"players":       players,
			"targetPlayers": matchmaking.CountdownPlayers,
			"maxPlayers":    matchmaking.MaxPlayers,
			"deadline":      deadline.UTC(),
		}))
	}
}

// beginGame gives every player of the room's new game its id and session state.
func (s *Server) beginGame(entry *roomEntry) {
	entry.gameID = "g_" + crand.Text()
	entry.reported = nil
	g := entry.room.Game()
	entry.profiles = map[string]playerProfile{}
	for _, id := range g.PlayerIDs() {
		if player := s.players[id]; player != nil {
			player.gameID, player.game, player.gameRoom = entry.gameID, g, entry
			entry.profiles[id] = playerProfile{player.nickname, player.avatarID}
			s.sendSessionState(player)
		}
	}
}
