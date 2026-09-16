package api

import (
	"net/http"
	"testing"
)

// Hints and nicknames are shown to strangers, so both go through the
// blocklist the app stores require (App Store 1.2, Play UGC).

func TestBlockedNicknameIsRefused(t *testing.T) {
	c := newClient(t)
	body := map[string]string{"nickname": "שרמוטה", "avatarId": "avatar-m04-detective-hat"}
	status, got := c.do("POST", "/v1/sessions", "", body)
	c.wantError(http.StatusUnprocessableEntity, "nickname_blocked", status, got)

	// And it cannot be set later either.
	token, _ := c.session("דור")
	status, got = c.do("PATCH", "/v1/sessions/me", token, map[string]string{"nickname": "זונה"})
	c.wantError(http.StatusUnprocessableEntity, "nickname_blocked", status, got)
	if c.srv.players[c.srv.sessions[token].playerID].nickname != "דור" {
		t.Fatal("a refused update changed the nickname")
	}
}

func TestBlockedHintIsRefused(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(4)
	gameID, _ := c.startGame(roomID, players)

	for _, p := range players {
		wantOK(t, p.w.command("confirm", "game.confirmRole", map[string]any{"gameId": gameID}))
	}
	first := players[0].w.gameState(phase("hints"))["currentTurnPlayerId"]
	var turn *wsPlayer
	for _, p := range players {
		if p.id == first {
			turn = p
		}
	}
	if turn == nil {
		t.Fatal("nobody has the turn")
	}
	wantReplyError(t, turn.w.command("h1", "game.submitHint",
		map[string]any{"gameId": gameID, "text": "חרא"}), "hint_inappropriate")

	// An ordinary hint still goes through.
	wantOK(t, turn.w.command("h2", "game.submitHint",
		map[string]any{"gameId": gameID, "text": "אפור"}))
}

func TestReportRecordsAndValidates(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(4)
	gameID, _ := c.startGame(roomID, players)
	me, other := players[0], players[1]

	wantOK(t, me.w.command("r1", "game.report",
		map[string]any{"gameId": gameID, "playerId": other.id, "reason": "hint"}))
	if c.srv.metrics.reports != 1 {
		t.Fatalf("reports = %d, want 1", c.srv.metrics.reports)
	}

	for name, payload := range map[string]map[string]any{
		"no player":  {"gameId": gameID},
		"self":       {"gameId": gameID, "playerId": me.id},
		"a stranger": {"gameId": gameID, "playerId": "p_nobody"},
	} {
		t.Run(name, func(t *testing.T) {
			wantReplyError(t, me.w.command("r-"+name, "game.report", payload), "invalid_message")
		})
	}
	if c.srv.metrics.reports != 1 {
		t.Fatalf("reports = %d, want the invalid ones uncounted", c.srv.metrics.reports)
	}
}
