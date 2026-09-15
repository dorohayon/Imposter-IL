package api

import (
	"errors"
	"math/rand/v2"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
	"github.com/dorohayon/Imposter-IL/server/internal/room"
)

// PickWord chooses the category name and secret word for a game from the
// room's category ids (content.Pick in production). Without one, or with an
// incomplete game.Policy, room.start fails with content_unavailable.
type PickWord func(categoryIDs []string, rng *rand.Rand) (categoryName, word string, ok bool)

// leaveGame forgets the game this session was showing.
func (sess *session) leaveGame() { sess.gameID, sess.game, sess.gameRoom = "", nil, nil }

func (s *Server) startGame(sess *session, entry *roomEntry, now time.Time) string {
	v := entry.room.View()
	switch {
	case v.HostID != sess.playerID:
		return "not_room_host"
	case s.pickWord == nil:
		return "content_unavailable"
	}
	category, word, ok := s.pickWord(v.Settings.CategoryIDs, s.rng)
	if !ok {
		return "content_unavailable"
	}
	if err := entry.room.Start(sess.playerID, category, word, now); err != nil {
		if errors.Is(err, game.ErrInvalidSetup) {
			return "content_unavailable" // no inappropriate-words dictionary yet
		}
		return roomErrorCode(err)
	}
	s.beginGame(entry)
	s.publish(entry)
	return ""
}

func (s *Server) gameCommand(sess *session, typ string, p commandPayload, now time.Time) string {
	entry := sess.gameRoom
	if entry == nil || sess.gameID != p.GameID {
		return "game_not_found"
	}
	// A game replaced by a newer one in the room has ended; it can only be left.
	current := sess.game == entry.room.Game()
	if !current && typ != "game.leave" && typ != "game.playAgain" {
		return "game_not_found"
	}
	id := sess.playerID
	var err error
	switch typ {
	case "game.confirmRole":
		err = entry.room.WithGame(now, func(g *game.Game) error { return g.ConfirmRole(id, now) })
	case "game.submitHint":
		err = entry.room.WithGame(now, func(g *game.Game) error { return g.SubmitHint(id, p.Text, now) })
	case "game.react":
		if p.HintIndex == nil {
			return "invalid_message"
		}
		err = entry.room.WithGame(now, func(g *game.Game) error { return g.React(id, *p.HintIndex, p.ReactionID, now) })
		if err == nil {
			s.sendToGame(entry, message("game.reaction", now, map[string]any{
				"gameId": entry.gameID, "hintIndex": *p.HintIndex, "reactionId": p.ReactionID, "playerId": id,
			}))
		}
	case "game.vote":
		err = entry.room.WithGame(now, func(g *game.Game) error { return g.Vote(id, p.TargetPlayerID, now) })
	case "game.submitGuess":
		err = entry.room.WithGame(now, func(g *game.Game) error { return g.SubmitGuess(id, p.Text, now) })
	case "game.leave":
		// Leaving before the end is a loss; leaving the result screen is not.
		// Either way the player goes home, so they leave the room too.
		if current && s.currentRoom(sess) == entry {
			err = entry.room.Leave(id, now)
			sess.roomID = ""
		}
		sess.leaveGame()
		s.sendSessionState(sess)
	case "game.playAgain":
		v, viewErr := sess.game.View(id)
		if viewErr != nil || v.Phase != game.PhaseEnded {
			return "wrong_phase"
		}
		if entry.public {
			// Players who continue search again in the match's room, so they
			// stay together while new players fill the empty spots.
			return s.joinSearch(sess, entry, sess.searchCategories, now)
		}
		sess.leaveGame()
		s.sendSessionState(sess)
	default:
		return "invalid_message"
	}
	if err != nil {
		return gameErrorCode(err)
	}
	s.publish(entry)
	return ""
}

func gameErrorCode(err error) string {
	for target, code := range map[error]string{
		game.ErrWrongPhase:         "wrong_phase",
		game.ErrNotYourTurn:        "not_your_turn",
		game.ErrHintEmpty:          "hint_empty",
		game.ErrHintNotOneWord:     "hint_not_one_word",
		game.ErrHintTooLong:        "hint_too_long",
		game.ErrHintInappropriate:  "hint_inappropriate",
		game.ErrHintContainsSecret: "hint_contains_secret",
		game.ErrHintDuplicate:      "hint_duplicate",
		game.ErrInvalidHint:        "invalid_hint",
		game.ErrInvalidReaction:    "invalid_reaction",
		game.ErrSelfVote:           "self_vote",
		game.ErrInvalidVoteTarget:  "invalid_vote_target",
		game.ErrNotImpostor:        "not_impostor",
		game.ErrUnknownPlayer:      "unknown_player",
		game.ErrPlayerNotActive:    "player_not_active",
		room.ErrNoGame:             "game_not_found",
	} {
		if errors.Is(err, target) {
			return code
		}
	}
	return "internal_error"
}

// sendToGame queues msg for every player still showing the room's current game.
func (s *Server) sendToGame(entry *roomEntry, msg []byte) {
	g := entry.room.Game()
	if g == nil {
		return
	}
	for _, id := range g.PlayerIDs() {
		if player := s.players[id]; player != nil && player.game == g {
			s.queue(player.conn, msg)
		}
	}
}

// publishGame sends each player still showing the room's current game their
// own filtered view.
func (s *Server) publishGame(entry *roomEntry, now time.Time) {
	g := entry.room.Game()
	if g == nil {
		return
	}
	entry.stateVersion++ // above the room.state sent just before
	for _, id := range g.PlayerIDs() {
		if player := s.players[id]; player != nil && player.game == g {
			s.sendGameState(player, entry.stateVersion, now)
		}
	}
}

// sendGameState sends the player the game they are showing, which may be an
// earlier game of the room.
func (s *Server) sendGameState(player *session, stateVersion uint64, now time.Time) {
	if player.conn == nil || player.game == nil {
		return
	}
	if v, err := player.game.View(player.playerID); err == nil {
		s.queue(player.conn, message("game.state", now, map[string]any{"stateVersion": stateVersion, "game": s.gameJSON(player.gameID, v)}))
	}
}

type gamePlayerJSON struct {
	PlayerID      string            `json:"playerId"`
	Nickname      string            `json:"nickname"`
	AvatarID      string            `json:"avatarId"`
	Status        game.PlayerStatus `json:"status"`
	Connected     bool              `json:"connected"`
	Disconnects   int               `json:"disconnects"`
	RoleConfirmed bool              `json:"roleConfirmed"`
}

type hintJSON struct {
	PlayerID  string         `json:"playerId"`
	Text      string         `json:"text"`
	Missing   bool           `json:"missing"`
	Reactions map[string]int `json:"reactions"`
}

type resultJSON struct {
	Winner           *game.Team              `json:"winner"`
	Reason           game.EndReason          `json:"reason"`
	ImpostorPlayerID string                  `json:"impostorPlayerId"`
	SecretWord       string                  `json:"secretWord"`
	VoteRounds       []map[string]string     `json:"voteRounds"`
	Outcomes         map[string]game.Outcome `json:"outcomes"`
}

type gameJSON struct {
	GameID              string           `json:"gameId"`
	Phase               game.Phase       `json:"phase"`
	Deadline            *time.Time       `json:"deadline"`
	Category            string           `json:"category"`
	SecretWord          string           `json:"secretWord,omitempty"` // absent for the impostor until the end
	MyRole              game.Role        `json:"myRole"`
	Players             []gamePlayerJSON `json:"players"`
	CurrentTurnPlayerID *string          `json:"currentTurnPlayerId"`
	AwaitingReconnect   bool             `json:"awaitingReconnect"`
	Hints               []hintJSON       `json:"hints"`
	VoteCandidates      []string         `json:"voteCandidates"`
	MyVote              *string          `json:"myVote"`
	Result              *resultJSON      `json:"result"`
}

func optional[T comparable](v T) *T {
	var zero T
	if v == zero {
		return nil
	}
	return &v
}

func (s *Server) gameJSON(gameID string, v game.View) gameJSON {
	out := gameJSON{
		GameID:              gameID,
		Phase:               v.Phase,
		Category:            v.Category,
		SecretWord:          v.SecretWord,
		MyRole:              v.Role,
		Players:             []gamePlayerJSON{},
		CurrentTurnPlayerID: optional(v.CurrentTurn),
		AwaitingReconnect:   v.Reconnecting,
		Hints:               []hintJSON{},
		VoteCandidates:      append([]string{}, v.Candidates...),
		MyVote:              optional(v.MyVote),
	}
	if !v.Deadline.IsZero() {
		deadline := v.Deadline.UTC()
		out.Deadline = &deadline
	}
	for _, p := range v.Players {
		player := gamePlayerJSON{PlayerID: p.ID, Status: p.Status, Connected: p.Connected, Disconnects: p.Disconnects, RoleConfirmed: p.RoleConfirmed}
		if sess := s.players[p.ID]; sess != nil {
			player.Nickname, player.AvatarID = sess.nickname, sess.avatarID
		}
		out.Players = append(out.Players, player)
	}
	for _, h := range v.Hints {
		reactions := h.Reactions
		if reactions == nil {
			reactions = map[string]int{}
		}
		out.Hints = append(out.Hints, hintJSON{PlayerID: h.PlayerID, Text: h.Text, Missing: h.Missing, Reactions: reactions})
	}
	if r := v.Result; r != nil {
		out.Result = &resultJSON{
			Winner:           optional(r.Winner),
			Reason:           r.Reason,
			ImpostorPlayerID: r.ImpostorID,
			SecretWord:       r.SecretWord,
			VoteRounds:       r.VoteRounds,
			Outcomes:         r.Outcomes,
		}
	}
	return out
}
