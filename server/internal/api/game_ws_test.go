package api

import (
	"fmt"
	"math/rand/v2"
	"testing"
	"time"
)

type wsPlayer struct {
	id, token string
	w         *wsClient
}

// roomWithPlayers opens a room with n connected players; the first is host.
func (c *client) roomWithPlayers(n int) (string, []*wsPlayer) {
	c.t.Helper()
	var players []*wsPlayer
	var code, roomID string
	for i := range n {
		token, id := c.session(fmt.Sprintf("שחקן%d", i+1))
		if i == 0 {
			room := c.createRoom(token, 8)
			code, roomID = room["code"].(string), room["roomId"].(string)
		} else if status, body := c.join(token, code); status != 200 {
			c.t.Fatalf("join: %d %v", status, body)
		}
		players = append(players, &wsPlayer{id: id, token: token, w: c.dial(token)})
	}
	for _, p := range players {
		p.w.roomState(func(r map[string]any) bool { return len(r["players"].([]any)) == n })
	}
	return roomID, players
}

// gameState waits for a game.state whose game satisfies ok.
func (w *wsClient) gameState(ok func(g map[string]any) bool) map[string]any {
	w.t.Helper()
	for {
		payload := w.next("game.state")["payload"].(map[string]any)
		if g := payload["game"].(map[string]any); ok(g) {
			return g
		}
	}
}

func phase(want string) func(map[string]any) bool {
	return func(g map[string]any) bool { return g["phase"] == want }
}

func gamePlayer(g map[string]any, id string) map[string]any {
	for _, p := range g["players"].([]any) {
		if p := p.(map[string]any); p["playerId"] == id {
			return p
		}
	}
	return nil
}

// startGame starts the room's game and returns its id and the impostor.
func (c *client) startGame(roomID string, players []*wsPlayer) (string, string) {
	c.t.Helper()
	wantOK(c.t, players[0].w.command("start", "room.start", map[string]any{"roomId": roomID}))
	var gameID, impostor string
	for _, p := range players {
		gameID = p.w.sessionState(func(s map[string]any) bool { return s["activity"] == "game" })["gameId"].(string)
		g := p.w.gameState(phase("role_reveal"))
		_, hasWord := g["secretWord"]
		switch {
		case g["myRole"] == "impostor" && hasWord:
			c.t.Fatalf("the impostor received the secret word: %v", g)
		case g["myRole"] == "impostor":
			impostor = p.id
		case g["secretWord"] != "פיל" || g["category"] != "חיות":
			c.t.Fatalf("citizen view = %v", g)
		}
	}
	if impostor == "" {
		c.t.Fatal("nobody is the impostor")
	}
	return gameID, impostor
}

func (c *client) tick(roomID string) {
	c.srv.mu.Lock()
	defer c.srv.mu.Unlock()
	c.srv.tickRoom(c.srv.roomsByID[roomID])
}

func TestWSGamePlaysToTheEnd(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(4)
	byID := map[string]*wsPlayer{}
	for _, p := range players {
		byID[p.id] = p
	}
	host := players[0]

	wantReplyError(t, players[1].w.command("s0", "room.start", map[string]any{"roomId": roomID}), "not_room_host")
	gameID, impostor := c.startGame(roomID, players)
	host.w.roomState(func(r map[string]any) bool { return r["status"] == "in_game" })
	wantReplyError(t, host.w.command("too-early", "game.playAgain", map[string]any{"gameId": gameID}), "wrong_phase")

	for _, p := range players {
		wantOK(t, p.w.command("confirm", "game.confirmRole", map[string]any{"gameId": gameID}))
	}
	g := host.w.gameState(phase("hints"))
	var order []string
	for _, p := range g["players"].([]any) {
		order = append(order, p.(map[string]any)["playerId"].(string))
	}
	if g["currentTurnPlayerId"] != order[0] || g["deadline"] != "2026-09-15T12:01:00Z" {
		t.Fatalf("first turn = %v", g)
	}

	hints := []string{"חדק", "אפור", "גדול", "זיכרון"}
	for i, id := range order {
		p := byID[id]
		if i > 0 {
			// Each hint is held so the table can read it; the next turn opens
			// when that ends.
			c.advance(3 * time.Second)
			c.tick(roomID)
		}
		if i == 0 {
			wantReplyError(t, byID[order[1]].w.command("early", "game.submitHint", map[string]any{"gameId": gameID, "text": "מוקדם"}), "not_your_turn")
			if id != impostor {
				wantReplyError(t, p.w.command("secret", "game.submitHint", map[string]any{"gameId": gameID, "text": "הפיל"}), "hint_contains_secret")
			}
		}
		wantOK(t, p.w.command("hint", "game.submitHint", map[string]any{"gameId": gameID, "text": hints[i]}))
		if i == 0 {
			// Reactions work while the next player is writing.
			reactor := byID[order[2]]
			wantReplyError(t, reactor.w.command("unapproved", "game.react", map[string]any{"gameId": gameID, "hintIndex": 0, "reactionId": "🔥"}), "invalid_reaction")
			wantOK(t, reactor.w.command("react", "game.react", map[string]any{"gameId": gameID, "hintIndex": 0, "reactionId": "laugh"}))
			if ev := host.w.next("game.reaction")["payload"].(map[string]any); ev["playerId"] != reactor.id || ev["reactionId"] != "laugh" {
				t.Fatalf("game.reaction = %v", ev)
			}
			host.w.gameState(func(g map[string]any) bool {
				hints := g["hints"].([]any)
				return len(hints) == 1 && hints[0].(map[string]any)["reactions"].(map[string]any)["laugh"] == float64(1)
			})
		}
	}

	// The last hint is held like the rest, then the board before the vote.
	host.w.gameState(phase("hint_break"))
	c.advance(3 * time.Second)
	c.tick(roomID)
	host.w.gameState(phase("pre_voting"))
	c.advance(5 * time.Second)
	c.tick(roomID)
	host.w.gameState(phase("voting"))
	for _, p := range players {
		target := impostor
		if p.id == impostor {
			wantReplyError(t, p.w.command("self", "game.vote", map[string]any{"gameId": gameID, "targetPlayerId": impostor}), "self_vote")
			target = order[0]
			if target == impostor {
				target = order[1]
			}
		}
		wantOK(t, p.w.command("vote", "game.vote", map[string]any{"gameId": gameID, "targetPlayerId": target}))
	}

	c.advance(20 * time.Second)
	c.tick(roomID)
	byID[impostor].w.gameState(phase("impostor_guess"))
	citizen := order[0]
	if citizen == impostor {
		citizen = order[1]
	}
	wantReplyError(t, byID[citizen].w.command("guess", "game.submitGuess", map[string]any{"gameId": gameID, "text": "פיל"}), "not_impostor")
	wantOK(t, byID[impostor].w.command("guess", "game.submitGuess", map[string]any{"gameId": gameID, "text": "הַפִּיל"}))

	end := host.w.gameState(phase("ended"))
	result := end["result"].(map[string]any)
	outcomes := result["outcomes"].(map[string]any)
	if result["winner"] != "impostor" || result["reason"] != "impostor_guessed_word" || result["impostorPlayerId"] != impostor ||
		outcomes[impostor] != "win" || outcomes[citizen] != "loss" || end["secretWord"] != "פיל" {
		t.Fatalf("result = %v", end)
	}
	host.w.roomState(func(r map[string]any) bool { return r["status"] == "lobby" })

	// Leaving the result screen repeats the authoritative result in
	// session.state, so a client can recover it after a dropped reply.
	resultLeaver := players[1]
	wantOK(t, resultLeaver.w.command("result-home", "game.leave", map[string]any{"gameId": gameID}))
	if state := resultLeaver.w.sessionState(func(s map[string]any) bool { return s["activity"] == "none" }); state["lastGameId"] != gameID || state["lastGameOutcome"] != outcomes[resultLeaver.id] {
		t.Fatalf("result leave session.state = %v", state)
	}

	wantReplyError(t, host.w.command("wrong", "game.vote", map[string]any{"gameId": "g_nope", "targetPlayerId": impostor}), "game_not_found")
	wantOK(t, host.w.command("again", "game.playAgain", map[string]any{"gameId": gameID}))
	host.w.sessionState(func(s map[string]any) bool { return s["activity"] == "room" && s["roomId"] == roomID })
	wantReplyError(t, host.w.command("after", "game.confirmRole", map[string]any{"gameId": gameID}), "game_not_found")
}

func TestWSRoleRevealAdvancesOnTheTimer(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(4)
	c.startGame(roomID, players)
	c.srv.mu.Lock()
	scheduled := c.srv.roomsByID[roomID].timer != nil
	c.srv.mu.Unlock()
	if !scheduled {
		t.Fatal("no timer for the role reveal deadline")
	}

	c.advance(19 * time.Second)
	c.tick(roomID) // not due yet: nothing is published
	c.advance(time.Second)
	c.tick(roomID)
	for _, p := range players {
		p.w.gameState(phase("hints"))
	}
}

func TestWSStartWithoutContentIsRefused(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(4)
	c.srv.mu.Lock()
	c.srv.pickWord = nil
	c.srv.mu.Unlock()
	wantReplyError(t, players[0].w.command("start", "room.start", map[string]any{"roomId": roomID}), "content_unavailable")

	c.srv.mu.Lock()
	c.srv.pickWord = func([]string, *rand.Rand) (string, string, bool) { return "", "", false }
	c.srv.mu.Unlock()
	wantReplyError(t, players[0].w.command("start2", "room.start", map[string]any{"roomId": roomID}), "content_unavailable")
}

func TestWSLeavingAGameIsALossAndLeavesTheRoom(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(5)
	gameID, impostor := c.startGame(roomID, players)
	leaver, watcher := players[1], players[2]
	if leaver.id == impostor {
		leaver = players[3]
	}
	if watcher.id == impostor || watcher == leaver {
		watcher = players[4]
	}

	wantOK(t, leaver.w.command("bye", "game.leave", map[string]any{"gameId": gameID}))
	if state := leaver.w.sessionState(func(s map[string]any) bool { return s["activity"] == "none" }); state["lastGameId"] != gameID || state["lastGameOutcome"] != "loss" {
		t.Fatalf("active leave session.state = %v", state)
	}
	watcher.w.gameState(func(g map[string]any) bool { return gamePlayer(g, leaver.id)["status"] == "left" })
	watcher.w.roomState(func(r map[string]any) bool { return member(r, leaver.id) == nil && r["status"] == "in_game" })
	wantReplyError(t, leaver.w.command("late", "game.confirmRole", map[string]any{"gameId": gameID}), "game_not_found")
}

func TestWSRemovedPlayerStillSeesTheGame(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(4)
	gameID, _ := c.startGame(roomID, players)
	host, victim := players[0], players[1]

	for i := range 3 {
		_ = victim.w.ws.CloseNow()
		host.w.gameState(func(g map[string]any) bool { return gamePlayer(g, victim.id)["disconnects"] == float64(i+1) })
		if i < 2 {
			victim.w = c.dial(victim.token)
			host.w.gameState(func(g map[string]any) bool { return gamePlayer(g, victim.id)["connected"] == true })
		}
	}
	c.advance(30 * time.Second)
	c.tick(roomID)
	host.w.gameState(func(g map[string]any) bool { return gamePlayer(g, victim.id)["status"] == "removed" })

	// Coming back shows the game with my removal (screen 27), not the room.
	victim.w = c.dial(victim.token)
	if s := victim.w.sessionState(func(map[string]any) bool { return true }); s["activity"] != "game" || s["gameId"] != gameID {
		t.Fatalf("session.state = %v", s)
	}
	victim.w.gameState(func(g map[string]any) bool { return gamePlayer(g, victim.id)["status"] == "removed" })
	wantOK(t, victim.w.command("home", "game.leave", map[string]any{"gameId": gameID}))
	victim.w.sessionState(func(s map[string]any) bool { return s["activity"] == "none" })
}

func TestWSCommandAfterADeadlinePublishesTheAdvanceEvenWhenItFails(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(4)
	gameID, _ := c.startGame(roomID, players)
	byID := map[string]*wsPlayer{}
	for _, p := range players {
		byID[p.id] = p
		wantOK(t, p.w.command("confirm", "game.confirmRole", map[string]any{"gameId": gameID}))
	}
	var order []string
	for _, p := range players[0].w.gameState(phase("hints"))["players"].([]any) {
		order = append(order, p.(map[string]any)["playerId"].(string))
	}

	// The first turn expires. The timer has not run, and the next command
	// comes from a player whose turn it still is not.
	c.advance(60 * time.Second)
	wantReplyError(t, byID[order[2]].w.command("late", "game.submitHint", map[string]any{"gameId": gameID, "text": "מאוחר"}), "not_your_turn")
	byID[order[3]].w.gameState(func(g map[string]any) bool { return g["currentTurnPlayerId"] == order[1] })
}

func TestWSPlayerRemovedFromAnEarlierGameCanStillSeeAndLeaveIt(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(5)
	oldGameID, impostor := c.startGame(roomID, players)
	// The victim and the watcher are citizens; either may be the host.
	var citizens []*wsPlayer
	for _, p := range players {
		if p.id != impostor {
			citizens = append(citizens, p)
		}
	}
	victim, watcher := citizens[0], citizens[1]

	for i := range 3 {
		_ = victim.w.ws.CloseNow()
		watcher.w.gameState(func(g map[string]any) bool { return gamePlayer(g, victim.id)["disconnects"] == float64(i+1) })
		if i < 2 {
			victim.w = c.dial(victim.token)
			watcher.w.gameState(func(g map[string]any) bool { return gamePlayer(g, victim.id)["connected"] == true })
		}
	}
	c.advance(30 * time.Second)
	c.tick(roomID)
	watcher.w.gameState(func(g map[string]any) bool { return gamePlayer(g, victim.id)["status"] == "removed" })

	// The impostor leaves, the first game ends, and a second one starts.
	wantOK(t, byID(players, impostor).w.command("bye", "game.leave", map[string]any{"gameId": oldGameID}))
	watcher.w.gameState(phase("ended"))
	newToken, _ := c.session("חדש")
	c.join(newToken, c.roomCode(roomID))
	c.dial(newToken)
	lobby := watcher.w.roomState(func(r map[string]any) bool { return r["status"] == "lobby" && len(r["players"].([]any)) == 4 })
	host := byID(players, lobby["hostPlayerId"].(string))
	wantOK(t, host.w.command("start2", "room.start", map[string]any{"roomId": roomID}))
	watcher.w.sessionState(func(s map[string]any) bool { return s["activity"] == "game" && s["gameId"] != oldGameID })

	victim.w = c.dial(victim.token)
	if s := victim.w.sessionState(func(map[string]any) bool { return true }); s["gameId"] != oldGameID {
		t.Fatalf("session.state = %v", s)
	}
	victim.w.gameState(func(g map[string]any) bool {
		return g["gameId"] == oldGameID && g["phase"] == "ended" && gamePlayer(g, victim.id)["status"] == "removed"
	})
	wantReplyError(t, victim.w.command("old", "game.confirmRole", map[string]any{"gameId": oldGameID}), "game_not_found")
	wantOK(t, victim.w.command("home", "game.leave", map[string]any{"gameId": oldGameID}))
	victim.w.sessionState(func(s map[string]any) bool { return s["activity"] == "none" })
}

func byID(players []*wsPlayer, id string) *wsPlayer {
	for _, p := range players {
		if p.id == id {
			return p
		}
	}
	return nil
}

func (c *client) roomCode(roomID string) string {
	c.srv.mu.Lock()
	defer c.srv.mu.Unlock()
	return c.srv.roomsByID[roomID].room.View().Code
}

func TestWSSnapshotVersionsKeepRisingAcrossTypes(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(4)
	gameID, _ := c.startGame(roomID, players)
	w := players[0].w
	w.skipped = nil // keep only what arrives from here on

	wantOK(t, w.command("confirm", "game.confirmRole", map[string]any{"gameId": gameID}))
	last, seen := 0.0, 0
	for _, msg := range w.skipped {
		if msg["type"] != "room.state" && msg["type"] != "game.state" {
			continue
		}
		v := msg["payload"].(map[string]any)["stateVersion"].(float64)
		if v <= last {
			t.Fatalf("%s stateVersion %v after %v", msg["type"], v, last)
		}
		last, seen = v, seen+1
	}
	if seen < 2 {
		t.Fatalf("only %d snapshots seen", seen)
	}
}

// The result screen names everyone who played. Nicknames used to be read from
// live sessions, so a player whose session had gone by then — every staging
// bot, whose session is deleted the moment the match settles — showed blank.
func TestFinishedGameStillNamesPlayersWhoseSessionIsGone(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(4)
	c.startGame(roomID, players)
	host, gone := players[0], players[3]

	// The session disappears while the game is still on screen.
	c.srv.mu.Lock()
	delete(c.srv.players, gone.id)
	delete(c.srv.sessions, gone.token)
	c.srv.mu.Unlock()

	// Any publish re-renders the view for everyone still watching.
	wantOK(t, host.w.command("confirm", "game.confirmRole", map[string]any{"gameId": c.srv.players[host.id].gameID}))
	g := host.w.gameState(func(map[string]any) bool { return true })
	if p := gamePlayer(g, gone.id); p == nil || p["nickname"] == "" {
		t.Fatalf("player with no session lost their name: %v", p)
	}
	if p := gamePlayer(g, gone.id); p["avatarId"] == "" {
		t.Fatalf("player with no session lost their avatar: %v", p)
	}
}
