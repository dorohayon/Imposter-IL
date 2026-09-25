package api

import (
	"context"
	"fmt"
	"testing"
)

// How many legitimate, rate-limit-compliant reactions does it take to
// disconnect a player whose socket writer is stalled (network hiccup, app
// briefly backgrounded)? The victim's conn is swapped for one with the real
// 64-slot buffer and no writer draining it.
func TestAuditReactionBurstOverflowsAStalledPlayer(t *testing.T) {
	c := newClient(t)
	roomID, players := c.roomWithPlayers(6)
	gameID, _ := c.startGame(roomID, players)
	for _, p := range players {
		wantOK(t, p.w.command("confirm", "game.confirmRole", map[string]any{"gameId": gameID}))
	}
	reactor, victim := players[0], players[1]
	c.srv.mu.Lock()
	ctx, cancel := context.WithCancel(context.Background())
	stalled := &conn{send: make(chan []byte, sendBuffer), ctx: ctx, cancel: cancel}
	c.srv.players[victim.id].conn = stalled
	c.srv.mu.Unlock()

	sent, okCount := 0, 0
	for i := range 60 { // within the command limiter's burst
		msg := reactor.w.command(fmt.Sprintf("r%d", i), "game.react", map[string]any{"gameId": gameID, "hintIndex": 0, "reactionId": "laugh"})
		sent++
		if msg["ok"] == true {
			okCount++
		}
		if ctx.Err() != nil {
			break
		}
	}
	bytes := 0
	for len(stalled.send) > 0 {
		bytes += len(<-stalled.send)
	}
	t.Logf("reactions sent: %d (ok %d); victim disconnected: %v; bytes queued for victim: %d", sent, okCount, ctx.Err() != nil, bytes)
	if ctx.Err() != nil {
		t.Errorf("a burst of %d reactions (limiter burst is %d) disconnected a player whose socket stalled", sent, commandsBurst)
	}
}
