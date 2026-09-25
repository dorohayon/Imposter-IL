package api

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/matchmaking"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

// searcher signs a player in, connects, and starts an online search.
func (c *client) searcher(name string, categories ...string) *wsPlayer {
	c.t.Helper()
	token, id := c.session(name)
	p := &wsPlayer{id: id, token: token, w: c.dial(token)}
	p.w.sessionState(func(s map[string]any) bool { return s["activity"] == "none" })
	wantOK(c.t, p.w.command("search", "matchmaking.join", map[string]any{"categoryIds": categories}))
	p.w.sessionState(func(s map[string]any) bool { return s["activity"] == "matchmaking" })
	return p
}

func TestStagingBotsFillYieldAndNeverWaitAlone(t *testing.T) {
	c := newClient(t)
	c.srv.EnableStagingBots(5)
	first := c.searcher("דור", "film_tv")
	c.advanceStagingBots(stagingBotJoinWindow)
	state := first.w.searchState(searchPlayers(6))
	botNames := 0
	for _, raw := range state["players"].([]any) {
		if name := raw.(map[string]any)["nickname"].(string); strings.HasPrefix(name, "בוט") {
			botNames++
		}
	}
	if botNames != 5 {
		t.Fatalf("players = %v, want one human and five named bots", state["players"])
	}

	second := c.searcher("נועה", "film_tv")
	first.w.searchState(func(state map[string]any) bool {
		players := state["players"].([]any)
		if len(players) != 4 {
			return false
		}
		for _, raw := range players {
			if raw.(map[string]any)["playerId"] == second.id {
				return true
			}
		}
		return false
	})

	c.srv.mu.Lock()
	bots := 0
	for _, sess := range c.srv.players {
		if sess.bot {
			bots++
		}
	}
	c.srv.mu.Unlock()
	if bots != 2 {
		t.Fatalf("bots after a second human = %d, want 2", bots)
	}

	wantOK(t, first.w.command("cancel-first", "matchmaking.cancel", map[string]any{}))
	wantOK(t, second.w.command("cancel-second", "matchmaking.cancel", map[string]any{}))
	c.srv.mu.Lock()
	defer c.srv.mu.Unlock()
	for _, sess := range c.srv.players {
		if sess.bot {
			t.Fatal("bots remained after the last human left")
		}
	}
}

func TestStagingBotsPlayAnOnlineGameToCompletion(t *testing.T) {
	c := newClient(t)
	c.srv.EnableStagingBots(5)
	human := c.searcher("דור", "film_tv")
	c.waitStagingSearchPlayers(4)
	c.advance(30 * time.Second)
	c.tickAll()
	session := human.w.sessionState(func(state map[string]any) bool { return state["activity"] == "game" })
	gameID := session["gameId"].(string)
	human.w.gameState(phase("role_reveal"))

	wantOK(t, human.w.command("confirm", "game.confirmRole", map[string]any{"gameId": gameID}))
	// A match now runs several hint-and-vote rounds before it ends.
	for step := 0; step < 160; step++ {
		c.srv.runStagingBots()
		c.srv.mu.Lock()
		sess := c.srv.players[human.id]
		view, err := sess.game.View(human.id)
		c.srv.mu.Unlock()
		if err != nil {
			t.Fatal(err)
		}
		switch view.Phase {
		case game.PhaseHints:
			if view.CurrentTurn == human.id {
				wantOK(t, human.w.command(fmt.Sprintf("hint-%d", step), "game.submitHint", map[string]any{
					// A new word each turn: the duplicate rule spans the match.
					"gameId": gameID, "text": fmt.Sprintf("אנושי%d", step),
				}))
			} else {
				// A bot spends stagingBotWriteSeconds appearing to write.
				c.advance(stagingBotWriteSeconds * time.Second)
				c.tickAll()
			}
		case game.PhaseHintBreak:
			// Each hint is held so the table can read it.
			c.advance(3 * time.Second)
			c.tickAll()
		case game.PhasePreVoting:
			// The board is held for a beat before the vote opens.
			c.advance(5 * time.Second)
			c.tickAll()
		case game.PhaseVoting, game.PhaseRunoffVoting:
			// The table can vote the human out too, and a spectator does not
			// vote.
			playing := false
			for _, p := range view.Players {
				if p.ID == human.id {
					playing = p.Status == game.StatusActive
				}
			}
			if playing && view.MyVote == "" {
				var target string
				for _, candidate := range view.Candidates {
					if candidate != human.id {
						target = candidate
						break
					}
				}
				wantOK(t, human.w.command(fmt.Sprintf("vote-%d", step), "game.vote", map[string]any{
					"gameId": gameID, "targetPlayerId": target,
				}))
			}
			// Long enough for the bots to finish deliberating, then for the
			// round itself to close.
			c.advance(stagingBotVoteSeconds * time.Second)
			c.srv.runStagingBots()
			if view.Phase == game.PhaseVoting {
				c.advance(20 * time.Second)
			} else {
				c.advance(15 * time.Second)
			}
			c.tickAll()
		case game.PhaseEliminationReveal:
			c.advance(15 * time.Second)
			c.tickAll()
		case game.PhaseImpostorGuess:
			if view.Role == game.RoleImpostor {
				wantOK(t, human.w.command("guess", "game.submitGuess", map[string]any{
					"gameId": gameID, "text": "לאיודע",
				}))
			}
		case game.PhaseEnded:
			c.srv.mu.Lock()
			defer c.srv.mu.Unlock()
			for _, sess := range c.srv.players {
				if sess.bot {
					t.Fatal("finished match leaked a bot session")
				}
			}
			return
		}
	}
	t.Fatal("staging bots did not finish the game")
}

// searchState waits for a matchmaking.state that satisfies ok.
func (w *wsClient) searchState(ok func(state map[string]any) bool) map[string]any {
	w.t.Helper()
	for {
		if payload := w.next("matchmaking.state")["payload"].(map[string]any); ok(payload) {
			return payload
		}
	}
}

func searchPlayers(n int) func(map[string]any) bool {
	return func(s map[string]any) bool { return len(s["players"].([]any)) == n }
}

// advanceStagingBots moves the clock and runs the staging loop so scheduled
// search bots can join, as the server's Run loop would in production.
func (c *client) advanceStagingBots(window time.Duration) {
	const step = 350 * time.Millisecond
	for elapsed := time.Duration(0); elapsed <= window; elapsed += step {
		c.advance(step)
		c.srv.runStagingBots()
		c.tickAll()
	}
}

func (c *client) stagingSearchPlayerCount() int {
	c.srv.mu.Lock()
	defer c.srv.mu.Unlock()
	for _, entry := range c.srv.publicRooms {
		return len(entry.room.View().Members)
	}
	return 0
}

func (c *client) waitStagingSearchPlayers(n int) {
	for step := 0; step < 40; step++ {
		if c.stagingSearchPlayerCount() >= n {
			return
		}
		c.advance(350 * time.Millisecond)
		c.srv.runStagingBots()
		c.tickAll()
	}
	c.t.Fatalf("search did not reach %d players", n)
}

// tickAll applies every room's due deadlines, as the room timers would.
func (c *client) tickAll() {
	c.srv.mu.Lock()
	defer c.srv.mu.Unlock()
	for _, entry := range c.srv.roomsByID {
		c.srv.tickRoom(entry)
	}
}

func (c *client) searchers(n int, categories ...string) []*wsPlayer {
	var players []*wsPlayer
	for i := range n {
		players = append(players, c.searcher(fmt.Sprintf("מחפש%d", i+1), categories...))
	}
	return players
}

// wantGameStarted checks every player got the same new game and returns each
// player's first game view.
func wantGameStarted(t *testing.T, players ...*wsPlayer) []map[string]any {
	t.Helper()
	var games []map[string]any
	for _, p := range players {
		p.w.sessionState(func(s map[string]any) bool { return s["activity"] == "game" })
		g := p.w.gameState(phase("role_reveal"))
		if len(g["players"].([]any)) != len(players) || g["category"] != "חיות" {
			t.Fatalf("game = %v", g)
		}
		games = append(games, g)
	}
	return games
}

func TestMatchmakingFourthPlayerStartsThirtySecondWait(t *testing.T) {
	c := newClient(t)
	players := c.searchers(3, "film_tv")
	s := players[0].w.searchState(searchPlayers(3))
	if s["status"] != "searching" || s["deadline"] != "2026-09-15T12:02:00Z" || s["targetPlayers"] != float64(6) || s["maxPlayers"] != float64(8) {
		t.Fatalf("searching state = %v", s)
	}

	c.advance(10 * time.Second)
	players = append(players, c.searcher("רביעי", "film_tv"))
	s = players[0].w.searchState(searchPlayers(4))
	if s["status"] != "waiting_for_more" || s["deadline"] != "2026-09-15T12:00:40Z" {
		t.Fatalf("waiting state = %v", s)
	}

	c.advance(29 * time.Second)
	c.tickAll()
	c.srv.mu.Lock()
	started := c.srv.players[players[0].id].gameID != ""
	c.srv.mu.Unlock()
	if started {
		t.Fatal("started before the wait ended")
	}
	c.advance(time.Second)
	c.tickAll()
	wantGameStarted(t, players...)
}

// roomID is the room the player's session is in, read from the server.
func (p *wsPlayer) roomID(c *client) string {
	c.srv.mu.Lock()
	defer c.srv.mu.Unlock()
	return c.srv.players[p.id].roomID
}

func TestMatchmakingSixthPlayerStartsCountdownThatSurvivesACancel(t *testing.T) {
	c := newClient(t)
	players := c.searchers(4, "film_tv")
	c.advance(5 * time.Second)
	players = append(players, c.searcher("חמישי", "film_tv"), c.searcher("שישי", "film_tv"))
	s := players[0].w.searchState(searchPlayers(6))
	if s["status"] != "countdown" || s["deadline"] != "2026-09-15T12:00:10Z" {
		t.Fatalf("countdown state = %v", s)
	}

	wantOK(t, players[5].w.command("cancel", "matchmaking.cancel", map[string]any{}))
	players[5].w.sessionState(func(s map[string]any) bool { return s["activity"] == "none" })
	if s := players[0].w.searchState(searchPlayers(5)); s["status"] != "countdown" {
		t.Fatalf("after a cancel = %v", s)
	}

	c.advance(5 * time.Second)
	c.tickAll()
	wantGameStarted(t, players[:5]...)
}

func TestMatchmakingDroppingBelowFourStartsAFreshWait(t *testing.T) {
	c := newClient(t)
	players := c.searchers(4, "film_tv")
	c.advance(10 * time.Second)
	wantOK(t, players[3].w.command("cancel", "matchmaking.cancel", map[string]any{}))
	if s := players[0].w.searchState(searchPlayers(3)); s["status"] != "searching" {
		t.Fatalf("below four = %v", s)
	}
	c.advance(10 * time.Second)
	wantOK(t, players[3].w.command("again", "matchmaking.join", map[string]any{"categoryIds": []string{"film_tv"}}))
	// Skip the older 4-player snapshot from before the cancel.
	players[0].w.searchState(func(s map[string]any) bool {
		return len(s["players"].([]any)) == 4 && s["deadline"] == "2026-09-15T12:00:50Z" && s["status"] == "waiting_for_more"
	})
}

func TestMatchmakingNoMatchAfterTwoMinutes(t *testing.T) {
	c := newClient(t)
	players := c.searchers(3, "film_tv")
	c.advance(2*time.Minute - time.Second)
	c.tickAll()
	if players[0].roomID(c) == "" {
		t.Fatal("no match before two minutes")
	}
	c.advance(time.Second)
	c.tickAll()
	for _, p := range players {
		if payload := p.w.next("matchmaking.noMatch")["payload"].(map[string]any); fmt.Sprint(payload["categoryIds"]) != "[animals]" {
			t.Fatalf("noMatch = %v", payload)
		}
		p.w.sessionState(func(s map[string]any) bool { return s["activity"] == "none" })
	}
}

func TestMatchmakingGroupsPlayersWhoShareACategory(t *testing.T) {
	c := newClient(t)
	food := c.searcher("אוכל", "food")
	animals := c.searcher("חיות", "film_tv")
	if food.roomID(c) == animals.roomID(c) {
		t.Fatal("players without a shared category were grouped")
	}
	both := c.searcher("שניהם", "food", "film_tv")
	if both.roomID(c) != food.roomID(c) {
		t.Fatal("a player with a shared category did not join the existing group")
	}
	if s := food.w.searchState(searchPlayers(2)); fmt.Sprint(s["categoryIds"]) != "[food]" {
		t.Fatalf("shared categories = %v", s)
	}
}

func TestMatchmakingErrors(t *testing.T) {
	c := newClient(t)
	token, _ := c.session("דור")
	w := c.dial(token)
	wantReplyError(t, w.command("bad", "matchmaking.join", map[string]any{"categoryIds": []string{"cars"}}), "invalid_categories")
	wantOK(t, w.command("ok", "matchmaking.join", map[string]any{"categoryIds": []string{"food"}}))
	wantReplyError(t, w.command("twice", "matchmaking.join", map[string]any{"categoryIds": []string{"food"}}), "already_in_activity")
	roomID := w.sessionState(func(s map[string]any) bool { return s["activity"] == "matchmaking" })["roomId"]
	wantReplyError(t, w.command("kick", "room.kick", map[string]any{"roomId": roomID, "playerId": "p_x"}), "room_not_found")

	host, _ := c.session("מנהל")
	c.createRoom(host, 8)
	hw := c.dial(host)
	wantReplyError(t, hw.command("busy", "matchmaking.join", map[string]any{"categoryIds": []string{"food"}}), "already_in_activity")

	c.srv.mu.Lock()
	c.srv.pickWord = nil
	c.srv.mu.Unlock()
	other, _ := c.session("אחר")
	wantReplyError(t, c.dial(other).command("nocontent", "matchmaking.join", map[string]any{"categoryIds": []string{"food"}}), "content_unavailable")
}

// A dropped connection keeps the place in the search for 30 s; closing the
// app for longer ends the search.
func TestMatchmakingADropKeepsThePlaceForThirtySeconds(t *testing.T) {
	c := newClient(t)
	players := c.searchers(2, "film_tv")
	players[0].w.searchState(searchPlayers(2))
	_ = players[1].w.ws.CloseNow()
	c.waitOffline(players[1].id)

	c.advance(29 * time.Second)
	c.tickAll()
	c.srv.mu.Lock()
	still := c.srv.players[players[1].id].roomID != ""
	c.srv.mu.Unlock()
	if !still {
		t.Fatal("a drop shorter than 30 s ended the search")
	}
	c.advance(time.Second)
	c.tickAll()
	players[0].w.searchState(searchPlayers(1))
}

// A searcher who is offline when the match starts is not dealt in: they may
// have cancelled on a phone that could not reach the server, and waking up
// inside that game would leave them only a losing way out.
func TestMatchmakingOfflineSearcherIsNotDealtIntoTheMatch(t *testing.T) {
	c := newClient(t)
	players := c.searchers(6, "film_tv")
	players[0].w.searchState(searchPlayers(6))
	gone := players[5]
	_ = gone.w.ws.CloseNow()
	c.waitOffline(gone.id)

	c.advance(matchmaking.Countdown) // the countdown ends with them away
	c.tickAll()
	c.srv.mu.Lock()
	sess := c.srv.players[gone.id]
	stillSearching, inGame := sess.roomID != "", sess.gameID != ""
	c.srv.mu.Unlock()
	if stillSearching || inGame {
		t.Fatalf("offline searcher: searching=%v inGame=%v, want neither", stillSearching, inGame)
	}

	// The five who stayed get their match once the timers run again.
	c.advance(matchmaking.Wait)
	c.tickAll()
	wantGameStarted(t, players[:5]...)
}

func TestMatchmakingReconnectingInTimeKeepsSearching(t *testing.T) {
	c := newClient(t)
	players := c.searchers(2, "film_tv")
	players[0].w.searchState(searchPlayers(2))
	_ = players[1].w.ws.CloseNow()
	c.waitOffline(players[1].id)
	c.advance(10 * time.Second)
	back := c.dial(players[1].token)
	if s := back.sessionState(func(map[string]any) bool { return true }); s["activity"] != "matchmaking" {
		t.Fatalf("session.state after a 10 s drop = %v, want still searching", s)
	}
	c.advance(30 * time.Second)
	c.tickAll()
	c.srv.mu.Lock()
	still := c.srv.players[players[1].id].roomID != ""
	c.srv.mu.Unlock()
	if !still {
		t.Fatal("the search ended after the player came back")
	}
}

func TestMatchmakingPlayAgainSearchesTogetherAndFillsUp(t *testing.T) {
	c := newClient(t)
	players := c.searchers(4, "film_tv")
	c.advance(30 * time.Second)
	c.tickAll()
	games := wantGameStarted(t, players...)

	var gameID, impostor string
	var rest []*wsPlayer
	for i, p := range players {
		s := games[i]
		gameID = s["gameId"].(string)
		if s["myRole"] == "impostor" {
			impostor = p.id
		} else {
			rest = append(rest, p)
		}
	}
	// The impostor leaving ends the game.
	wantOK(t, byID(players, impostor).w.command("bye", "game.leave", map[string]any{"gameId": gameID}))
	for _, p := range rest {
		p.w.gameState(phase("ended"))
	}

	wantOK(t, rest[0].w.command("again", "game.playAgain", map[string]any{"gameId": gameID}))
	wantOK(t, rest[1].w.command("again", "game.playAgain", map[string]any{"gameId": gameID}))
	if rest[0].roomID(c) != rest[1].roomID(c) {
		t.Fatal("players who chose another game were split up")
	}
	stranger := c.searcher("חדש", "film_tv")
	if stranger.roomID(c) != rest[0].roomID(c) {
		t.Fatal("a new player did not fill the continuing group")
	}
	rest[0].w.searchState(searchPlayers(3))

	// The player who stayed on the result screen still sees it and can leave.
	wantOK(t, rest[2].w.command("home", "game.leave", map[string]any{"gameId": gameID}))
	rest[2].w.sessionState(func(s map[string]any) bool { return s["activity"] == "none" })
}

func TestMatchmakingPlayAgainStaysTogetherEvenWithDifferentCategories(t *testing.T) {
	c := newClient(t)
	// Two of the four matched only on animals: one also picked food, one
	// also picked sports.
	players := []*wsPlayer{
		c.searcher("אוכל-וחיות", "food", "film_tv"),
		c.searcher("חיות", "film_tv"),
		c.searcher("ספורט-וחיות", "sports", "film_tv"),
		c.searcher("חיות2", "film_tv"),
	}
	c.advance(30 * time.Second)
	c.tickAll()
	games := wantGameStarted(t, players...)
	var gameID, impostor string
	for i, g := range games {
		gameID = g["gameId"].(string)
		if g["myRole"] == "impostor" {
			impostor = players[i].id
		}
	}

	// Bigger groups wait elsewhere: food lovers and sports fans.
	c.searchers(3, "food")
	c.searchers(3, "sports")

	wantOK(t, byID(players, impostor).w.command("bye", "game.leave", map[string]any{"gameId": gameID}))
	var rest []*wsPlayer
	for _, p := range players {
		if p.id != impostor {
			rest = append(rest, p)
		}
	}
	for _, p := range rest {
		p.w.gameState(phase("ended"))
		wantOK(t, p.w.command("again", "game.playAgain", map[string]any{"gameId": gameID}))
	}
	room := rest[0].roomID(c)
	for _, p := range rest[1:] {
		if p.roomID(c) != room {
			t.Fatal("players who chose another game were split into different groups")
		}
	}
}

// Bots react so that a single real player can see reactions arrive.
func TestStagingBotsReactToTheHintOnTheBoard(t *testing.T) {
	c := newClient(t)
	c.srv.EnableStagingBots(5)
	human := c.searcher("דור", "film_tv")
	c.waitStagingSearchPlayers(4)
	c.advance(30 * time.Second)
	c.tickAll()
	session := human.w.sessionState(func(state map[string]any) bool { return state["activity"] == "game" })
	gameID := session["gameId"].(string)
	human.w.gameState(phase("role_reveal"))
	wantOK(t, human.w.command("confirm", "game.confirmRole", map[string]any{"gameId": gameID}))

	view := func() (game.View, bool) {
		c.srv.mu.Lock()
		defer c.srv.mu.Unlock()
		sess := c.srv.players[human.id]
		if sess == nil || sess.game == nil {
			return game.View{}, false
		}
		v, err := sess.game.View(human.id)
		return v, err == nil
	}

	reactions := 0
	for step := 0; step < 40 && reactions == 0; step++ {
		c.srv.runStagingBots()
		v, ok := view()
		if !ok || v.Phase == game.PhaseEnded {
			break
		}
		if v.Phase == game.PhaseHints && v.CurrentTurn == human.id {
			wantOK(t, human.w.command(fmt.Sprintf("hint-%d", step), "game.submitHint", map[string]any{
				"gameId": gameID, "text": "אנושי",
			}))
		}
		// Long enough for a bot to finish reading and reach for a reaction.
		c.advance(3 * time.Second)
		c.tickAll()
		if v, ok := view(); ok {
			for _, h := range v.Hints {
				for _, n := range h.Reactions {
					reactions += n
				}
			}
		}
	}
	if reactions == 0 {
		t.Fatal("no bot reacted to any hint")
	}
}

// waitOffline waits until the server has seen the player's socket close, so a
// clock advance after it is measured from the drop.
func (c *client) waitOffline(playerID string) {
	c.t.Helper()
	for range 200 {
		c.srv.mu.Lock()
		gone := c.srv.players[playerID].conn == nil
		c.srv.mu.Unlock()
		if gone {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	c.t.Fatal("the server never saw the socket close")
}
