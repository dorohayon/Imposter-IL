package api

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"sync"
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

// lockedBuffer collects log lines written from the server's goroutines.
type lockedBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *lockedBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *lockedBuffer) lines(msg string) []map[string]any {
	b.mu.Lock()
	defer b.mu.Unlock()
	var out []map[string]any
	for _, line := range strings.Split(b.buf.String(), "\n") {
		var entry map[string]any
		if json.Unmarshal([]byte(line), &entry) == nil && entry["msg"] == msg {
			out = append(out, entry)
		}
	}
	return out
}

// Reports reach the operator with what was reported, and two different
// reporters hide a player's clues from the whole table (docs/moderation.md).
func TestReportsAreLoggedAndTwoHideThePlayerForEveryone(t *testing.T) {
	logs := &lockedBuffer{}
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(logs, nil)))
	t.Cleanup(func() { slog.SetDefault(previous) })

	c := newClient(t)
	roomID, players := c.roomWithPlayers(4)
	gameID, _ := c.startGame(roomID, players)
	for _, p := range players {
		wantOK(t, p.w.command("confirm", "game.confirmRole", map[string]any{"gameId": gameID}))
	}
	first := players[0].w.gameState(phase("hints"))["currentTurnPlayerId"]
	var author *wsPlayer
	var others []*wsPlayer
	for _, p := range players {
		if p.id == first {
			author = p
		} else {
			others = append(others, p)
		}
	}
	wantOK(t, author.w.command("hint", "game.submitHint", map[string]any{"gameId": gameID, "text": "אפור"}))
	reporterA, reporterB, bystander := others[0], others[1], others[2]
	report := func(by *wsPlayer, id string) {
		t.Helper()
		wantOK(t, by.w.command(id, "game.report", map[string]any{"gameId": gameID, "playerId": author.id, "hintIndex": 0}))
	}
	hintOf := func(w *wsClient) map[string]any {
		t.Helper()
		g := w.gameState(func(g map[string]any) bool { return len(g["hints"].([]any)) > 0 })
		return g["hints"].([]any)[0].(map[string]any)
	}

	report(reporterA, "r1")
	report(reporterA, "r1-again") // the same reporter twice is still one
	if h := hintOf(bystander.w); h["text"] != "אפור" || h["hidden"] == true {
		t.Fatalf("after one reporter the table still sees the clue, got %v", h)
	}

	report(reporterB, "r2")
	for {
		if h := hintOf(bystander.w); h["hidden"] == true {
			if h["text"] != "" {
				t.Fatalf("hidden clue still carries its text: %v", h)
			}
			break
		}
	}
	for {
		if h := hintOf(author.w); h["text"] == "אפור" {
			if h["hidden"] == true {
				t.Fatalf("the author is told their clue is hidden: %v", h)
			}
			break
		}
	}

	lines := logs.lines(reportLogMessage)
	if len(lines) != 3 {
		t.Fatalf("logged %d reports, want 3", len(lines))
	}
	last := lines[2]
	if last["hint"] != "אפור" || last["nickname"] == "" || last["playerId"] != author.id ||
		last["reporters"] != float64(2) || last["hiddenForAll"] != true || last["gameId"] != gameID {
		t.Fatalf("report log = %v", last)
	}
	if lines[1]["reporters"] != float64(1) {
		t.Fatalf("a repeat report counted as a new reporter: %v", lines[1])
	}
}
