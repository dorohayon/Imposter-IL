// Command loadbot drives simulated players through the real protocol, so the
// ceiling of the single-lock, single-process design is a measured number
// rather than the guess in docs/production-architecture-review.md (R6).
//
// It speaks docs/protocol.md over REST and WebSocket exactly as the app does;
// it shares no code with the server, so it also checks that the contract is
// what the app sees.
//
//	go run ./cmd/loadbot -server http://localhost:8080 -players 200 -for 2m
//
// The target server needs its per-IP limits off, since every bot dials from
// one address:
//
//	RATE_LIMITS=off go run ./cmd/server
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"maps"
	"math/rand/v2"
	"net/http"
	"os"
	"os/signal"
	"slices"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"
)

var (
	server    = flag.String("server", "http://localhost:8080", "base URL of the server under test")
	players   = flag.Int("players", 64, "simulated players, in multiples of 8 for full tables")
	duration  = flag.Duration("for", time.Minute, "how long to keep playing")
	rampUp    = flag.Duration("ramp", 5*time.Second, "spread player arrival over this long")
	reactRate = flag.Float64("react", 0.3, "chance a bot reacts to each new hint")
	// Matchmaking only groups players whose categories intersect, so bots
	// joining a human's search have to share at least one with them.
	categories = flag.String("categories", "food,animals,sports,professions,places,objects",
		"comma-separated category ids to search with; the default matches anyone")
	// Bots that answer in microseconds make a game with a human in it feel
	// broken: hints appear before the turn is readable. Thinking time makes a
	// bot-filled match look like a real one. Set 0 for capacity tests, where
	// the point is to push the server as hard as possible.
	thinkMin = flag.Duration("think-min", 2*time.Second, "shortest pause before a bot acts")
	thinkMax = flag.Duration("think-max", 7*time.Second, "longest pause before a bot acts")
)

// hintWords are ordinary describing words. They are deliberately not drawn
// from the game's own categories, so a bot can never accidentally submit the
// secret word and be refused.
var hintWords = []string{
	"גדול", "קטן", "צהוב", "מהיר", "אדום", "חם", "קר", "עגול",
	"רועש", "מתוק", "כבד", "ישן", "חדש", "רך", "חזק", "יפה",
	"מוזר", "כחול", "ארוך", "קצר", "שקט", "חלק", "כתום", "מבריק",
}

// think pauses for a human-looking moment, or returns early if the game moves
// on without this bot.
func think(ctx context.Context) bool {
	if *thinkMax <= 0 {
		return true
	}
	d := *thinkMin
	if *thinkMax > *thinkMin {
		d += time.Duration(rand.Int64N(int64(*thinkMax - *thinkMin)))
	}
	select {
	case <-time.After(d):
		return true
	case <-ctx.Done():
		return false
	}
}

func main() {
	flag.Parse()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	ctx, cancel := context.WithTimeout(ctx, *duration)
	defer cancel()

	stats := &stats{codes: map[string]int{}}
	var wg sync.WaitGroup
	for i := range *players {
		wg.Add(1)
		go func() {
			defer wg.Done()
			// Spread arrivals so the run measures steady state, not a stampede.
			select {
			case <-ctx.Done():
				return
			case <-time.After(time.Duration(float64(*rampUp) * float64(i) / float64(*players))):
			}
			if err := (&bot{id: i, stats: stats}).play(ctx); err != nil && ctx.Err() == nil {
				stats.fail(err)
			}
		}()
	}
	wg.Wait()
	stats.report(*players, *duration)
}

// ------------------------------------------------------------------ stats

type stats struct {
	mu       sync.Mutex
	latency  []time.Duration // reply latency per command
	codes    map[string]int  // reply error code, "ok" for success
	games    int
	failures int
	lastErr  error
}

func (s *stats) record(d time.Duration, code string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.latency = append(s.latency, d)
	if code == "" {
		code = "ok"
	}
	s.codes[code]++
}

func (s *stats) gameEnded() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.games++
}

func (s *stats) fail(err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.failures++
	s.lastErr = err
}

func (s *stats) report(players int, ran time.Duration) {
	s.mu.Lock()
	defer s.mu.Unlock()
	sort.Slice(s.latency, func(i, j int) bool { return s.latency[i] < s.latency[j] })
	at := func(q float64) time.Duration {
		if len(s.latency) == 0 {
			return 0
		}
		return s.latency[min(int(float64(len(s.latency))*q), len(s.latency)-1)]
	}
	fmt.Printf("\nplayers      %d over %s\n", players, ran)
	fmt.Printf("commands     %d\n", len(s.latency))
	fmt.Printf("games ended  %d\n", s.games)
	fmt.Printf("latency      p50 %v   p95 %v   p99 %v   max %v\n",
		at(.50).Round(time.Microsecond), at(.95).Round(time.Microsecond),
		at(.99).Round(time.Microsecond), at(1).Round(time.Microsecond))
	for _, code := range slices.Sorted(maps.Keys(s.codes)) {
		fmt.Printf("  %-28s %d\n", code, s.codes[code])
	}
	if s.failures > 0 {
		fmt.Printf("bot failures %d (last: %v)\n", s.failures, s.lastErr)
	}
	fmt.Println("\nRead imposter_publish_seconds_sum / imposter_publish_total and heap from")
	fmt.Println("the server's /metrics alongside this; together they are the capacity number.")
}

// -------------------------------------------------------------------- bot

var hintCounter atomic.Int64

type bot struct {
	id       int
	stats    *stats
	playerID string
	ws       *websocket.Conn

	mu      sync.Mutex
	pending map[string]chan string // message id -> error code

	// Snapshots to act on. The read loop must never block on a write, or the
	// server's slow-consumer guard drops the connection.
	snapshots chan json.RawMessage
	// Hint index this bot has already reacted to. Reacting on every snapshot
	// instead would be a feedback loop: a reaction publishes a snapshot, which
	// prompts another reaction.
	reactedTo int
	// thinking guards the pause before a hint, so the snapshots that arrive
	// while a bot composes do not start a second one.
	thinking bool
	// phase is the last one seen, read by the thinking goroutines: a command
	// decided on before a pause is pointless once the game has moved past it,
	// and the server rejects it as wrong_phase.
	phase string
}

// stillIn reports whether the game is still in the phase the bot was thinking
// about. Both it and the writer hold b.mu, so the read is race-free.
func (b *bot) stillIn(phase string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.phase == phase
}

func (b *bot) setPhase(phase string) {
	b.mu.Lock()
	b.phase = phase
	b.mu.Unlock()
}

// unusedWord picks a describing word no one has played in this game yet, so
// the server never refuses it as a duplicate.
func unusedWord(g gameView) string {
	used := map[string]bool{}
	for _, h := range g.Hints {
		used[h.Text] = true
	}
	start := int(hintCounter.Add(1)) % len(hintWords)
	for i := range hintWords {
		if w := hintWords[(start+i)%len(hintWords)]; !used[w] {
			return w
		}
	}
	return hintWords[start]
}

func (b *bot) play(ctx context.Context) error {
	token, err := b.createSession(ctx)
	if err != nil {
		return fmt.Errorf("session: %w", err)
	}
	ws, _, err := websocket.Dial(ctx, wsURL(*server), &websocket.DialOptions{
		HTTPHeader: http.Header{
			"Authorization":   {"Bearer " + token},
			"X-Client-Build":  {"1"},
			"X-Loadbot-Index": {fmt.Sprint(b.id)},
		},
	})
	if err != nil {
		return fmt.Errorf("dial: %w", err)
	}
	defer func() { _ = ws.CloseNow() }()
	ws.SetReadLimit(1 << 20)
	b.ws, b.pending = ws, map[string]chan string{}
	b.snapshots, b.reactedTo = make(chan json.RawMessage, 8), -1

	go b.actLoop(ctx)
	go b.search(ctx)
	return b.read(ctx)
}

func (b *bot) createSession(ctx context.Context) (string, error) {
	body := fmt.Sprintf(`{"nickname":"בוט%d","avatarId":"avatar-m01-flashlight"}`, b.id)
	req, _ := http.NewRequestWithContext(ctx, "POST", *server+"/v1/sessions", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Client-Build", "1")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()
	var out struct {
		PlayerID     string `json:"playerId"`
		SessionToken string `json:"sessionToken"`
		Error        struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", err
	}
	if resp.StatusCode != http.StatusCreated {
		return "", fmt.Errorf("%d %s", resp.StatusCode, out.Error.Code)
	}
	b.playerID = out.PlayerID
	return out.SessionToken, nil
}

func (b *bot) search(ctx context.Context) {
	b.send(ctx, "matchmaking.join", map[string]any{"categoryIds": categoryIDs()})
}

func categoryIDs() []string {
	var out []string
	for _, id := range strings.Split(*categories, ",") {
		if id = strings.TrimSpace(id); id != "" {
			out = append(out, id)
		}
	}
	return out
}

// read reacts to every snapshot the server sends, which is the whole bot: the
// server is authoritative, so there is no local model to keep.
func (b *bot) read(ctx context.Context) error {
	for {
		_, data, err := b.ws.Read(ctx)
		if err != nil {
			return err
		}
		var msg struct {
			Type    string                `json:"type"`
			ReplyTo string                `json:"replyTo"`
			Error   struct{ Code string } `json:"error"`
			Payload struct {
				Game json.RawMessage `json:"game"`
			} `json:"payload"`
		}
		if json.Unmarshal(data, &msg) != nil {
			continue
		}
		switch msg.Type {
		case "reply":
			b.mu.Lock()
			if ch, ok := b.pending[msg.ReplyTo]; ok {
				delete(b.pending, msg.ReplyTo)
				ch <- msg.Error.Code
			}
			b.mu.Unlock()
		case "game.state":
			// Drop rather than block: snapshots are whole states, so only the
			// newest matters.
			select {
			case b.snapshots <- msg.Payload.Game:
			default:
			}
		}
	}
}

type gameView struct {
	GameID      string   `json:"gameId"`
	Phase       string   `json:"phase"`
	MyRole      string   `json:"myRole"`
	CurrentTurn string   `json:"currentTurnPlayerId"`
	MyVote      string   `json:"myVote"`
	Candidates  []string `json:"voteCandidates"`
	Hints       []struct {
		PlayerID string `json:"playerId"`
		Text     string `json:"text"`
	} `json:"hints"`
	Players []struct {
		PlayerID      string `json:"playerId"`
		Status        string `json:"status"`
		RoleConfirmed bool   `json:"roleConfirmed"`
	} `json:"players"`
}

func (b *bot) actLoop(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case raw := <-b.snapshots:
			b.act(ctx, raw)
		}
	}
}

func (b *bot) act(ctx context.Context, raw json.RawMessage) {
	var g gameView
	if len(raw) == 0 || json.Unmarshal(raw, &g) != nil {
		return
	}
	b.setPhase(g.Phase)
	switch g.Phase {
	case "role_reveal":
		b.reactedTo = -1 // a new game
		for _, p := range g.Players {
			if p.PlayerID == b.playerID && !p.RoleConfirmed {
				b.send(ctx, "game.confirmRole", map[string]any{"gameId": g.GameID})
			}
		}
	case "hints":
		if g.CurrentTurn == b.playerID {
			if b.thinking {
				return // already composing this turn
			}
			b.thinking = true
			hint := unusedWord(g)
			go func() {
				// Take a few seconds, the way a player does. The turn timer is
				// 15 seconds, so this still lands in time — unless the turn
				// passed while thinking, in which case there is nothing to send.
				if think(ctx) && b.stillIn("hints") {
					b.send(ctx, "game.submitHint", map[string]any{"gameId": g.GameID, "text": hint})
				}
				b.thinking = false
			}()
		} else if last := len(g.Hints) - 1; last > b.reactedTo {
			// Once per new hint, the way a player reacts. Reactions are the
			// heaviest path: each one fans a full snapshot out to everyone.
			b.reactedTo = last
			if rand.Float64() < *reactRate {
				b.send(ctx, "game.react", map[string]any{
					"gameId": g.GameID, "hintIndex": last, "reactionId": "laugh",
				})
			}
		}
	case "voting", "runoff_voting":
		if g.MyVote != "" || b.thinking {
			return
		}
		for _, id := range candidates(g) {
			if id == b.playerID {
				continue
			}
			b.thinking = true
			phase := g.Phase
			go func() {
				// Deliberating, so the votes do not all land in the same frame.
				if think(ctx) && b.stillIn(phase) {
					b.send(ctx, "game.vote", map[string]any{"gameId": g.GameID, "targetPlayerId": id})
				}
				b.thinking = false
			}()
			return
		}
	case "impostor_guess":
		if g.MyRole == "impostor" {
			b.send(ctx, "game.submitGuess", map[string]any{"gameId": g.GameID, "text": "פיל"})
		}
	case "ended":
		if b.reactedTo == -2 {
			return // already asked for another game
		}
		b.reactedTo = -2
		b.stats.gameEnded()
		b.send(ctx, "game.playAgain", map[string]any{"gameId": g.GameID})
	}
}

func candidates(g gameView) []string {
	if len(g.Candidates) > 0 {
		return g.Candidates
	}
	var out []string
	for _, p := range g.Players {
		if p.Status == "active" {
			out = append(out, p.PlayerID)
		}
	}
	return out
}

// send writes a command and records how long the reply took.
func (b *bot) send(ctx context.Context, typ string, payload any) {
	id := fmt.Sprintf("%d-%d", b.id, hintCounter.Add(1))
	msg, _ := json.Marshal(map[string]any{"v": 1, "id": id, "type": typ, "payload": payload})

	ch := make(chan string, 1)
	b.mu.Lock()
	b.pending[id] = ch
	b.mu.Unlock()

	start := time.Now()
	if err := b.ws.Write(ctx, websocket.MessageText, msg); err != nil {
		b.mu.Lock()
		delete(b.pending, id)
		b.mu.Unlock()
		return
	}
	go func() {
		select {
		case code := <-ch:
			b.stats.record(time.Since(start), code)
		case <-time.After(15 * time.Second):
			b.stats.record(time.Since(start), "TIMEOUT")
		case <-ctx.Done():
		}
	}()
}

func wsURL(base string) string {
	url := strings.Replace(strings.Replace(base, "https://", "wss://", 1), "http://", "ws://", 1)
	return strings.TrimSuffix(url, "/") + "/v1/ws"
}

func init() { log.SetFlags(0) }
