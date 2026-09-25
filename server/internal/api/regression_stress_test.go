package api

// Concurrency audit: adversarial schedules against one in-memory server.
// Run: go test -race -run 'TestAudit' -count=1 ./internal/api/

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"net/http"
	"net/http/httptest"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
)

type auditPlayer struct {
	id, token string
	mu        sync.Mutex
	ws        *websocket.Conn
	all       []*websocket.Conn // every socket dialled, closed at teardown
	roomID    string
	gameID    string
	code      string
}

func (p *auditPlayer) ids() (string, string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.roomID, p.gameID
}

func auditDial(ctx context.Context, url, token string) (*websocket.Conn, error) {
	h := http.Header{}
	h.Set("Authorization", "Bearer "+token)
	dctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	ws, _, err := websocket.Dial(dctx, "ws"+strings.TrimPrefix(url, "http")+"/v1/ws", &websocket.DialOptions{HTTPHeader: h})
	return ws, err
}

// reader drains a connection and records the ids session.state reports.
func (p *auditPlayer) reader(ws *websocket.Conn) {
	for {
		_, data, err := ws.Read(context.Background())
		if err != nil {
			return
		}
		var msg struct {
			Type    string `json:"type"`
			Payload struct {
				RoomID string `json:"roomId"`
				GameID string `json:"gameId"`
				Room   struct {
					Code string `json:"code"`
				} `json:"room"`
			} `json:"payload"`
		}
		if json.Unmarshal(data, &msg) != nil {
			continue
		}
		p.mu.Lock()
		switch msg.Type {
		case "session.state":
			p.roomID, p.gameID = msg.Payload.RoomID, msg.Payload.GameID
		case "room.state":
			if msg.Payload.Room.Code != "" {
				p.code = msg.Payload.Room.Code
			}
		}
		p.mu.Unlock()
	}
}

func (p *auditPlayer) connect(ctx context.Context, url string) {
	ws, err := auditDial(ctx, url, p.token)
	if err != nil {
		return
	}
	p.mu.Lock()
	old := p.ws
	p.ws = ws
	p.all = append(p.all, ws)
	p.mu.Unlock()
	if old != nil && rand.IntN(2) == 0 {
		_ = old.CloseNow() // sometimes the old socket lingers: replaced-connection path
	}
	go p.reader(ws)
}

func (p *auditPlayer) send(typ string, payload map[string]any) {
	p.mu.Lock()
	ws := p.ws
	p.mu.Unlock()
	if ws == nil {
		return
	}
	b, _ := json.Marshal(map[string]any{"v": 1, "id": fmt.Sprintf("%d", rand.Int64()), "type": typ, "payload": payload})
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	_ = ws.Write(ctx, websocket.MessageText, b)
}

func auditREST(ts *httptest.Server, method, path, token string, body any) {
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest(method, ts.URL+path, strings.NewReader(string(b)))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := ts.Client().Do(req)
	if err == nil {
		_ = res.Body.Close()
	}
}

// TestAuditStressOneServer hammers a handful of rooms with every kind of
// event at once: commands, REST, reconnects, drops, fake-clock jumps that fire
// deadlines, the reaper and the staging-bot loop. It asserts the server lock is
// still obtainable afterwards, no panic was recovered, and goroutines return
// to baseline.
func TestAuditStressOneServer(t *testing.T) {
	procs := []int{1, 2, 8}
	for _, gmp := range procs {
		t.Run(fmt.Sprintf("GOMAXPROCS=%d", gmp), func(t *testing.T) {
			prev := runtime.GOMAXPROCS(gmp)
			defer runtime.GOMAXPROCS(prev)
			auditStress(t, 3*time.Second)
		})
	}
}

func auditStress(t *testing.T, runFor time.Duration) {
	base := runtime.NumGoroutine()
	c := newClient(t)
	c.srv.commandLimit = newLimiter(0, 0)
	c.srv.EnableStagingBots(5)
	ts := c.ts

	ctx, cancel := context.WithCancel(context.Background())
	var players []*auditPlayer
	for i := range 16 {
		token, id := c.session(fmt.Sprintf("שחקן%d", i))
		p := &auditPlayer{id: id, token: token}
		players = append(players, p)
		p.connect(ctx, ts.URL)
	}
	// Two private rooms of six, the rest search online.
	for r := range 2 {
		host := players[r*6]
		room := c.createRoom(host.token, 8)
		for _, p := range players[r*6+1 : r*6+6] {
			c.join(p.token, room["code"].(string))
		}
		host.mu.Lock()
		host.code = room["code"].(string)
		host.mu.Unlock()
	}
	codes := func() []string {
		var out []string
		for _, p := range players {
			p.mu.Lock()
			if p.code != "" {
				out = append(out, p.code)
			}
			p.mu.Unlock()
		}
		return out
	}

	var wg sync.WaitGroup
	stop := make(chan struct{})
	var ops, botLoopPanics atomic.Int64
	loop := func(fn func(r *rand.Rand)) {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r := rand.New(rand.NewPCG(rand.Uint64(), rand.Uint64()))
			for {
				select {
				case <-stop:
					return
				default:
				}
				fn(r)
				ops.Add(1)
			}
		}()
	}
	pick := func(r *rand.Rand) *auditPlayer { return players[r.IntN(len(players))] }
	cats := [][]string{{"film_tv"}, {"film_tv", "food"}, {"food"}}
	for range 12 {
		loop(func(r *rand.Rand) {
			p := pick(r)
			roomID, gameID := p.ids()
			target := pick(r).id
			hint := r.IntN(6)
			switch r.IntN(16) {
			case 0:
				p.send("room.start", map[string]any{"roomId": roomID})
			case 1:
				p.send("room.kick", map[string]any{"roomId": roomID, "playerId": target})
			case 2:
				p.send("room.leave", map[string]any{"roomId": roomID})
			case 3:
				p.send("matchmaking.join", map[string]any{"categoryIds": cats[r.IntN(len(cats))]})
			case 4:
				p.send("matchmaking.cancel", nil)
			case 5:
				p.send("game.confirmRole", map[string]any{"gameId": gameID})
			case 6:
				p.send("game.submitHint", map[string]any{"gameId": gameID, "text": fmt.Sprintf("רמז%d", r.IntN(1000))})
			case 7:
				p.send("game.react", map[string]any{"gameId": gameID, "hintIndex": hint, "reactionId": "laugh"})
			case 8:
				p.send("game.vote", map[string]any{"gameId": gameID, "targetPlayerId": target})
			case 9:
				p.send("game.submitGuess", map[string]any{"gameId": gameID, "text": "פיל"})
			case 10:
				p.send("game.leave", map[string]any{"gameId": gameID})
			case 11:
				p.send("game.playAgain", map[string]any{"gameId": gameID})
			case 12:
				p.send("game.report", map[string]any{"gameId": gameID, "playerId": target, "hintIndex": hint})
			case 13:
				p.send("game.continueAfterElimination", map[string]any{"gameId": gameID})
			case 14:
				p.send("room.updateSettings", map[string]any{"roomId": roomID, "maxPlayers": 8, "hintSeconds": 30, "categoryIds": []string{"food"}})
			case 15:
				p.send("game.confirmRole", map[string]any{"gameId": gameID})
			}
		})
	}
	// REST from the same sessions.
	for range 4 {
		loop(func(r *rand.Rand) {
			p := pick(r)
			switch r.IntN(5) {
			case 0:
				auditREST(ts, "PATCH", "/v1/sessions/me", p.token, map[string]any{"nickname": fmt.Sprintf("שם%d", r.IntN(99))})
			case 1:
				if cs := codes(); len(cs) > 0 {
					auditREST(ts, "POST", "/v1/rooms/join", p.token, map[string]any{"code": cs[r.IntN(len(cs))]})
				}
			case 2:
				auditREST(ts, "POST", "/v1/rooms", p.token, map[string]any{"maxPlayers": 8, "hintSeconds": 60, "categoryIds": []string{"film_tv"}})
			case 3:
				auditREST(ts, "POST", "/v1/entitlements", p.token, map[string]any{"purchases": []any{}})
			case 4:
				auditREST(ts, "GET", "/v1/config", "", nil)
			}
		})
	}
	// Reconnects and drops.
	for range 3 {
		loop(func(r *rand.Rand) {
			p := pick(r)
			if r.IntN(3) == 0 {
				p.mu.Lock()
				if p.ws != nil {
					_ = p.ws.CloseNow()
				}
				p.mu.Unlock()
			}
			p.connect(ctx, ts.URL)
			time.Sleep(time.Duration(r.IntN(20)) * time.Millisecond)
		})
	}
	// Time: jumps that fire deadlines, the reaper, staging bots, real timers.
	loop(func(r *rand.Rand) {
		c.advance(time.Duration(r.IntN(25_000)) * time.Millisecond)
		// As the room timers run it: recovered, the room aborted.
		c.srv.mu.Lock()
		for _, entry := range c.srv.roomsByID {
			func() {
				defer c.srv.recoverRoom(entry, "timer")
				c.srv.tickRoom(entry)
			}()
		}
		c.srv.mu.Unlock()
		// Server.Run has no recover here; count what would have killed the process.
		func() {
			defer func() {
				if p := recover(); p != nil {
					botLoopPanics.Add(1)
					t.Logf("runStagingBots panic (process crash in production): %v", p)
				}
			}()
			c.srv.runStagingBots()
		}()
		if r.IntN(10) == 0 {
			c.advance(11 * time.Minute) // makes idle sessions and empty rooms reapable
			c.srv.reap()
		}
		time.Sleep(time.Millisecond)
	})
	loop(func(r *rand.Rand) {
		c.srv.Metrics(httptest.NewRecorder(), nil)
		_ = c.srv.ActiveGames()
		time.Sleep(5 * time.Millisecond)
	})

	time.Sleep(runFor)
	close(stop)
	wg.Wait()
	cancel()

	// The server lock must still be obtainable: a panic under it without
	// recovery would leave it held forever.
	got := make(chan struct{})
	go func() { c.srv.mu.Lock(); close(got); c.srv.mu.Unlock() }()
	select {
	case <-got:
	case <-time.After(5 * time.Second):
		buf := make([]byte, 1<<20)
		t.Fatalf("server lock still held after the run:\n%s", buf[:runtime.Stack(buf, true)])
	}
	c.srv.mu.Lock()
	panics, aborted := c.srv.metrics.panics, c.srv.metrics.aborted
	// Every searching public room member must have a session: matchmaking
	// dereferences s.players[id] without a nil check.
	for _, e := range c.srv.publicRooms {
		for _, m := range e.room.View().Members {
			if c.srv.players[m.ID] == nil {
				t.Errorf("public room %s member %s has no session", e.id, m.ID)
			}
		}
	}
	for _, sess := range c.srv.players {
		if (sess.game == nil) != (sess.gameRoom == nil) || (sess.game == nil) != (sess.gameID == "") {
			t.Errorf("session %s has inconsistent game fields", sess.playerID)
		}
	}
	c.srv.mu.Unlock()
	t.Logf("ops=%d recovered panics=%d aborted=%d bot-loop panics=%d", ops.Load(), panics, aborted, botLoopPanics.Load())
	if panics != 0 {
		t.Errorf("%d panics recovered during the run", panics)
	}

	// Goroutine leak check: close every socket and the server, then settle.
	for _, p := range players {
		p.mu.Lock()
		// Every socket, not only the latest: two racing dials can leave the
		// server holding the one the player no longer points at.
		for _, ws := range p.all {
			_ = ws.CloseNow()
		}
		p.mu.Unlock()
	}
	ts.CloseClientConnections()
	ts.Close()
	// A socket's goroutines may take up to two ping intervals (20 s) to see
	// a dead peer; only what outlives that is a leak.
	deadline := time.Now().Add(30 * time.Second)
	for runtime.NumGoroutine() > base+2 && time.Now().Before(deadline) {
		time.Sleep(50 * time.Millisecond)
	}
	if n := runtime.NumGoroutine(); n > base+2 {
		buf := make([]byte, 1<<20)
		t.Errorf("goroutines: %d before, %d after settling\n%s", base, n, buf[:runtime.Stack(buf, true)])
	}
}
