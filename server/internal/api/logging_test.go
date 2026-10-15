package api

import (
	"log/slog"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

// One game, followed in the log by its ids alone: every step a player takes
// and every phase the game enters, and none of the words typed or dealt.
func TestAGameCanBeFollowedInTheLogWithoutItsWords(t *testing.T) {
	logs := &lockedBuffer{}
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(logs, &slog.HandlerOptions{Level: slog.LevelDebug})))
	t.Cleanup(func() { slog.SetDefault(previous) })

	c := newClient(t)
	roomID, players := c.roomWithPlayers(4)
	host := players[0]
	gameID, _ := c.startGame(roomID, players)
	for _, p := range players {
		wantOK(t, p.w.command("confirm", "game.confirmRole", map[string]any{"gameId": gameID}))
	}
	first := host.w.gameState(phase("hints"))["currentTurnPlayerId"]
	wantOK(t, byID(players, first.(string)).w.command("hint", "game.submitHint", map[string]any{"gameId": gameID, "text": "אפור"}))
	for range 200 {
		c.advance(5 * time.Second)
		c.tick(roomID)
		c.srv.mu.Lock()
		v, _ := c.srv.players[host.id].game.View(host.id)
		c.srv.mu.Unlock()
		if v.Phase == game.PhaseEnded {
			break
		}
	}

	if n := len(logs.lines("session created")); n != 4 {
		t.Fatalf("logged %d sessions, want 4", n)
	}
	if n := len(logs.lines("connected")); n < 4 {
		t.Fatalf("logged %d connections, want 4", n)
	}
	if len(logs.lines("room created")) != 1 || len(logs.lines("room joined")) != 3 {
		t.Fatal("room created/joined not logged")
	}
	if started := logs.lines("game started"); len(started) != 1 || started[0]["gameId"] != gameID || started[0]["roomId"] != roomID {
		t.Fatalf("game started = %v", started)
	}
	phases := map[any]bool{}
	for _, l := range logs.lines("game phase") {
		phases[l["phase"]] = true
	}
	if !phases["role_reveal"] || !phases["hints"] || !phases["voting"] {
		t.Fatalf("phases logged = %v", phases)
	}
	ended := logs.lines("game ended")
	if len(ended) != 1 || ended[0]["gameId"] != gameID || len(ended[0]["outcomes"].(map[string]any)) != 4 {
		t.Fatalf("game ended = %v", ended)
	}
	confirms := 0
	for _, l := range logs.lines("command") {
		if l["type"] == "game.confirmRole" && l["code"] == "ok" && l["gameId"] == gameID && l["playerId"] != "" {
			confirms++
		}
	}
	if confirms != 4 {
		t.Fatalf("logged %d role confirmations, want 4", confirms)
	}

	// The query in deploy/README.md: playerId, or playerIds for the game's
	// own lines, finds a player's whole game.
	mine := map[any]bool{}
	for _, msg := range []string{"session created", "connected", "command", "game started", "game phase", "game ended"} {
		for _, l := range logs.lines(msg) {
			ids, _ := l["playerIds"].([]any)
			if l["playerId"] == host.id || slices.Contains(ids, any(host.id)) {
				mine[msg] = true
			}
		}
	}
	if len(mine) != 6 {
		t.Fatalf("a search by playerId finds only %v", mine)
	}

	// The secret word, the hint and the nicknames (שחקן1…) stay out.
	logs.mu.Lock()
	all := logs.buf.String()
	logs.mu.Unlock()
	for _, secret := range []string{"פיל", "אפור", "שחקן"} {
		if strings.Contains(all, secret) {
			t.Fatalf("the log contains %q", secret)
		}
	}
}
