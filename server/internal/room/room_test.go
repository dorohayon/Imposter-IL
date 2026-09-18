package room

import (
	"errors"
	"math/rand/v2"
	"slices"
	"testing"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

var t0 = time.Date(2026, 9, 15, 12, 0, 0, 0, time.UTC)

func testPolicy() game.Policy {
	return game.Policy{
		HintInappropriate: func(string) bool { return false },
		ValidReaction:     func(string) bool { return true },
	}
}

func settings() Settings {
	return Settings{MaxPlayers: 8, HintSeconds: 60, CategoryIDs: []string{"animals"}}
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func wantErr(t *testing.T, got, want error) {
	t.Helper()
	if !errors.Is(got, want) {
		t.Fatalf("error = %v, want %v", got, want)
	}
}

func wantHost(t *testing.T, r *Room, id string) {
	t.Helper()
	if r.host != id {
		t.Fatalf("host = %q, want %q", r.host, id)
	}
}

// newRoom opens a room hosted by "host" with the given extra players joined in order.
func newRoom(t *testing.T, s Settings, players ...string) *Room {
	t.Helper()
	r, err := New("012345", "host", s, testPolicy(), rand.New(rand.NewPCG(1, 2)), t0)
	must(t, err)
	for i, id := range players {
		must(t, r.Join(id, t0.Add(time.Duration(i+1)*time.Second)))
	}
	return r
}

func TestNewValidatesCodeAndSettings(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 2))
	cases := map[string]struct {
		code string
		s    Settings
		want error
	}{
		"short code":     {"12345", settings(), ErrInvalidCode},
		"letters":        {"12a456", settings(), ErrInvalidCode},
		"three players":  {"123456", Settings{3, 15, []string{"c"}}, ErrInvalidSettings},
		"nine players":   {"123456", Settings{9, 15, []string{"c"}}, ErrInvalidSettings},
		"12 second hint": {"123456", Settings{8, 12, []string{"c"}}, ErrInvalidSettings},
		"no categories":  {"123456", Settings{8, 15, nil}, ErrInvalidSettings},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := New(c.code, "host", c.s, testPolicy(), rng, t0)
			wantErr(t, err, c.want)
		})
	}
	for _, s := range []Settings{{4, 30, []string{"a"}}, {8, 90, []string{"a", "b"}}} {
		if _, err := New("000000", "host", s, testPolicy(), rng, t0); err != nil {
			t.Fatalf("%+v: %v", s, err)
		}
	}
}

func TestNewCodeIsSixDigits(t *testing.T) {
	rng := rand.New(rand.NewPCG(3, 4))
	for range 200 {
		if code := NewCode(rng); !ValidCode(code) {
			t.Fatalf("invalid code %q", code)
		}
	}
}

func TestJoinLocksSettingsAndRespectsCapacity(t *testing.T) {
	r := newRoom(t, Settings{MaxPlayers: 4, HintSeconds: 60, CategoryIDs: []string{"a"}})
	must(t, r.UpdateSettings("host", Settings{MaxPlayers: 5, HintSeconds: 30, CategoryIDs: []string{"b"}}, t0))

	must(t, r.Join("p1", t0))
	wantErr(t, r.UpdateSettings("host", settings(), t0), ErrSettingsLocked)
	version := r.View().Version
	must(t, r.Join("p1", t0)) // a repeated join is not an error
	if r.View().Version != version || len(r.View().Members) != 2 {
		t.Fatal("repeated join changed the room")
	}

	wantErr(t, r.Join("", t0), ErrInvalidPlayerID)
	if len(r.View().Members) != 2 {
		t.Fatal("an empty player id became a member")
	}
	must(t, r.Join("p2", t0))
	must(t, r.Join("p3", t0))
	must(t, r.Join("p4", t0))
	wantErr(t, r.Join("p5", t0), ErrRoomFull)

	// The lock stays after the other players leave.
	for _, id := range []string{"p1", "p2", "p3", "p4"} {
		must(t, r.Leave(id, t0))
	}
	if v := r.View(); !v.SettingsLocked || v.Settings.HintSeconds != 30 {
		t.Fatalf("view = %+v", v)
	}
}

func TestOnlyHostKicksOtherPlayersFromLobby(t *testing.T) {
	r := newRoom(t, settings(), "p1", "p2")
	wantErr(t, r.Kick("p1", "p2", t0), ErrNotHost)
	wantErr(t, r.Kick("host", "host", t0), ErrCannotKickSelf)
	wantErr(t, r.Kick("host", "nobody", t0), ErrUnknownPlayer)
	must(t, r.Kick("host", "p2", t0))
	if len(r.View().Members) != 2 {
		t.Fatal("kicked player still in the room")
	}
	// A removed player may rejoin with the code (docs/decisions.md).
	must(t, r.Join("p2", t0.Add(time.Second)))
}

func TestStartIncludesOfflineMembersAndUsesHintSeconds(t *testing.T) {
	s := settings()
	s.HintSeconds = 30
	r := newRoom(t, s, "p1", "p2")
	wantErr(t, r.Start("p1", "animals", "פיל", t0), ErrNotHost)
	wantErr(t, r.Start("host", "animals", "פיל", t0), ErrNotEnoughPlayers)

	must(t, r.Join("p3", t0))
	must(t, r.Disconnect("p3", t0))
	must(t, r.Start("host", "animals", "פיל", t0))
	if r.View().Status != StatusInGame {
		t.Fatal("room did not enter the game")
	}
	wantInGame := func(connected bool) {
		t.Helper()
		v, err := r.Game().View("p3")
		must(t, err)
		i := slices.IndexFunc(v.Players, func(p game.PlayerView) bool { return p.ID == "p3" })
		if v.Players[i].Connected != connected || v.Players[i].Disconnects != 0 {
			t.Fatalf("p3 in game = %+v, want connected=%v with no counted disconnect", v.Players[i], connected)
		}
	}
	wantInGame(false)
	wantErr(t, r.Join("p5", t0), ErrInGame)
	wantErr(t, r.Kick("host", "p1", t0), ErrInGame)
	wantErr(t, r.Start("host", "animals", "פיל", t0), ErrInGame)

	must(t, r.Reconnect("p3", t0))
	wantInGame(true)

	confirmAll(t, r, t0)
	if want := t0.Add(30 * time.Second); !r.Deadline().Equal(want) {
		t.Fatalf("first hint deadline = %v, want %v", r.Deadline(), want)
	}
}

func TestStartByServerNeedsNoHost(t *testing.T) {
	r := newRoom(t, settings(), "p1", "p2")
	wantErr(t, r.StartByServer("animals", "פיל", t0), ErrNotEnoughPlayers)
	must(t, r.Join("p3", t0))
	must(t, r.StartByServer("animals", "פיל", t0))
	if r.View().Status != StatusInGame {
		t.Fatal("room did not enter the game")
	}
	wantErr(t, r.StartByServer("animals", "פיל", t0), ErrInGame)
}

func confirmAll(t *testing.T, r *Room, now time.Time) {
	t.Helper()
	for _, id := range r.participants {
		must(t, r.WithGame(now, func(g *game.Game) error { return g.ConfirmRole(id, now) }))
	}
}

func impostor(t *testing.T, r *Room) string {
	t.Helper()
	for _, id := range r.participants {
		if v, _ := r.Game().View(id); v.Role == game.RoleImpostor {
			return id
		}
	}
	t.Fatal("no impostor")
	return ""
}

func TestFinishedGameReturnsToLobbyAndRoomStaysOpen(t *testing.T) {
	r := newRoom(t, settings(), "p1", "p2", "p3", "p4")
	wantErr(t, r.WithGame(t0, func(*game.Game) error { return nil }), ErrNoGame)
	must(t, r.Start("host", "animals", "פיל", t0))
	confirmAll(t, r, t0)

	// The impostor leaving ends the game (impostor_gone) and leaves the room.
	gone := impostor(t, r)
	must(t, r.Leave(gone, t0.Add(time.Second)))
	v := r.View()
	if v.Status != StatusLobby || len(v.Members) != 4 {
		t.Fatalf("room after the game = %+v", v)
	}
	if res, _ := r.Game().View(r.participants[0]); res.Result == nil || res.Result.Reason != game.ReasonImpostorGone {
		t.Fatal("the last game's result must stay readable")
	}

	must(t, r.Join("p5", t0.Add(2*time.Second)))
	must(t, r.Start(r.host, "animals", "נמר", t0.Add(3*time.Second)))
}

// disconnectThreeTimes leaves playerID offline on their third disconnect and
// returns when that happened.
func disconnectThreeTimes(t *testing.T, r *Room, playerID string) time.Time {
	t.Helper()
	now := t0
	for i := range game.MaxDisconnects {
		if i > 0 {
			must(t, r.Reconnect(playerID, now))
			now = now.Add(time.Second)
		}
		must(t, r.Disconnect(playerID, now))
	}
	return now
}

func TestPlayerRemovedFromGameLeavesRoom(t *testing.T) {
	r := newRoom(t, settings(), "p1", "p2", "p3", "p4")
	must(t, r.Start("host", "animals", "פיל", t0))
	now := disconnectThreeTimes(t, r, "p1")
	r.Tick(now.Add(29 * time.Second))
	if r.member("p1") == nil {
		t.Fatal("removed before the reconnect window ended")
	}
	r.Tick(now.Add(30 * time.Second))
	if r.member("p1") != nil {
		t.Fatal("player removed after the third disconnect is still a member")
	}
}

func TestHostTimeoutGoesToLongestPresentConnectedMember(t *testing.T) {
	r := newRoom(t, settings(), "p1", "p2", "p3")
	must(t, r.Disconnect("p1", t0))
	must(t, r.Disconnect("host", t0))
	if want := t0.Add(30 * time.Second); !r.Deadline().Equal(want) || !r.View().HostReconnectDeadline.Equal(want) {
		t.Fatalf("host deadline = %v", r.Deadline())
	}

	r.Tick(t0.Add(29 * time.Second))
	wantHost(t, r, "host")
	r.Tick(t0.Add(30 * time.Second))
	wantHost(t, r, "p2") // p1 joined earlier but is offline
	if tr := r.View().HostTransfer; tr == nil || *tr != (HostTransfer{From: "host", To: "p2", Reason: ReasonHostTimeout}) {
		t.Fatalf("transfer = %+v", tr)
	}

	// The original host does not get the room back.
	must(t, r.Reconnect("host", t0.Add(31*time.Second)))
	wantHost(t, r, "p2")
	wantErr(t, r.Kick("host", "p3", t0.Add(31*time.Second)), ErrNotHost)
}

func TestHostReturningInTimeKeepsTheRoom(t *testing.T) {
	r := newRoom(t, settings(), "p1")
	must(t, r.Disconnect("host", t0))
	must(t, r.Reconnect("host", t0.Add(29*time.Second)))
	r.Tick(t0.Add(time.Minute))
	wantHost(t, r, "host")
	if v := r.View(); v.HostTransfer != nil || !v.HostReconnectDeadline.IsZero() {
		t.Fatalf("view = %+v", v)
	}
}

// timedOutWithNobodyOnline leaves the room without a host: the host missed the
// reconnect deadline while p1 and p2 were offline too.
func timedOutWithNobodyOnline(t *testing.T) *Room {
	t.Helper()
	r := newRoom(t, settings(), "p1", "p2")
	for _, id := range []string{"p1", "p2", "host"} {
		must(t, r.Disconnect(id, t0))
	}
	r.Tick(t0.Add(30 * time.Second))
	wantHost(t, r, "")
	if !r.Deadline().IsZero() || r.View().HostTransfer != nil {
		t.Fatal("nothing should be scheduled or transferred while waiting")
	}
	return r
}

func TestHostTimeoutWithNobodyOnlineGoesToFirstOtherMemberBack(t *testing.T) {
	r := timedOutWithNobodyOnline(t)

	// The original host coming back first does not get the room back.
	must(t, r.Reconnect("host", t0.Add(40*time.Second)))
	wantHost(t, r, "")
	wantErr(t, r.Kick("host", "p1", t0.Add(40*time.Second)), ErrNotHost)
	wantErr(t, r.Start("host", "animals", "פיל", t0.Add(40*time.Second)), ErrNotHost)

	must(t, r.Reconnect("p2", t0.Add(time.Minute)))
	wantHost(t, r, "p2")
	if tr := r.View().HostTransfer; tr == nil || *tr != (HostTransfer{From: "host", To: "p2", Reason: ReasonHostTimeout}) {
		t.Fatalf("transfer = %+v", tr)
	}
}

func TestHostTimeoutWithNobodyOnlineGoesToNewJoiner(t *testing.T) {
	r := timedOutWithNobodyOnline(t)
	must(t, r.Join("p3", t0.Add(time.Minute)))
	wantHost(t, r, "p3")
	if tr := r.View().HostTransfer; tr == nil || tr.From != "host" || tr.Reason != ReasonHostTimeout {
		t.Fatalf("transfer = %+v", tr)
	}
}

func TestHostLeavingHandsOverImmediately(t *testing.T) {
	r := newRoom(t, settings(), "p1", "p2")
	must(t, r.Disconnect("p1", t0))
	must(t, r.Leave("host", t0))
	wantHost(t, r, "p2")
	if r.View().HostTransfer.Reason != ReasonHostLeft {
		t.Fatal("wrong transfer reason")
	}

	// With only offline members left, the longest present one becomes host
	// and gets their own reconnect window.
	must(t, r.Leave("p2", t0))
	wantHost(t, r, "p1")
	if want := t0.Add(30 * time.Second); !r.Deadline().Equal(want) {
		t.Fatalf("new host deadline = %v, want %v", r.Deadline(), want)
	}

	must(t, r.Leave("p1", t0))
	if !r.Empty() || r.host != "" {
		t.Fatal("room should be empty without a host")
	}

	// The code still works, and the first player back runs the room.
	must(t, r.Join("p9", t0.Add(time.Minute)))
	wantHost(t, r, "p9")
	if v := r.View(); v.HostTransfer != nil || !v.HostReconnectDeadline.IsZero() {
		t.Fatalf("view = %+v", v)
	}
	must(t, r.Join("p10", t0.Add(time.Minute)))
	must(t, r.Kick("p9", "p10", t0.Add(time.Minute)))
}

func TestHostLeavingDuringGameIsALossAndHandsOver(t *testing.T) {
	r := newRoom(t, settings(), "p1", "p2", "p3", "p4")
	must(t, r.Start("host", "animals", "פיל", t0))
	confirmAll(t, r, t0)
	hostWasImpostor := impostor(t, r) == "host"

	must(t, r.Leave("host", t0))
	wantHost(t, r, "p1")
	v, _ := r.Game().View("host")
	if i := slices.IndexFunc(v.Players, func(p game.PlayerView) bool { return p.ID == "host" }); v.Players[i].Status != game.StatusLeft || v.Result != nil && v.Result.Outcomes["host"] != game.OutcomeLoss {
		t.Fatalf("host in game = %+v", v.Players[i])
	}
	// Five players continue unless the host was the impostor.
	if want := map[bool]Status{false: StatusInGame, true: StatusLobby}[hostWasImpostor]; r.View().Status != want {
		t.Fatalf("status = %s, want %s", r.View().Status, want)
	}
}

func TestHostRemovedOnThirdDisconnectInGame(t *testing.T) {
	r := newRoom(t, settings(), "p1", "p2", "p3", "p4")
	must(t, r.Start("host", "animals", "פיל", t0))
	now := disconnectThreeTimes(t, r, "host")

	// The game removal and the host timer end at the same moment.
	r.Tick(now.Add(30 * time.Second))
	if r.member("host") != nil {
		t.Fatal("removed host is still a member")
	}
	if tr := r.View().HostTransfer; tr == nil || tr.Reason != ReasonHostRemoved || tr.To != "p1" {
		t.Fatalf("transfer = %+v", tr)
	}
}

func TestViewIsASnapshot(t *testing.T) {
	r := newRoom(t, settings(), "p1")
	v := r.View()
	v.Members[0].ID = "changed"
	v.Settings.CategoryIDs[0] = "changed"
	if next := r.View(); next.Members[0].ID != "host" || next.Settings.CategoryIDs[0] != "animals" {
		t.Fatal("mutating a view changed the room")
	}
}

// A player the table voted out is still in the room. Losing membership would
// cost them their reconnect and, in a private room, the next game — which is
// what happened while the room dropped everyone who was not active.
func TestASpectatorKeepsTheirSeatInTheRoom(t *testing.T) {
	r := newRoom(t, settings(), "p1", "p2", "p3", "p4")
	must(t, r.Start("host", "animals", "פיל", t0))

	// Find a citizen, and hand the whole table's vote to them.
	var victim string
	for _, id := range []string{"host", "p1", "p2", "p3", "p4"} {
		v, err := r.Game().View(id)
		must(t, err)
		if v.Role == game.RoleCitizen {
			victim = id
			break
		}
	}

	// Straight to the vote: every turn simply times out.
	now := t0
	for r.Game().Phase() != game.PhaseVoting {
		now = now.Add(time.Minute)
		r.Tick(now)
		if r.Game().Phase() == game.PhaseEnded {
			t.Fatal("the match ended before a vote")
		}
	}
	for _, id := range []string{"host", "p1", "p2", "p3", "p4"} {
		if id == victim {
			continue
		}
		must(t, r.WithGame(now, func(g *game.Game) error { return g.Vote(id, victim, now) }))
	}
	now = now.Add(20 * time.Second)
	r.Tick(now)

	v, err := r.Game().View(victim)
	must(t, err)
	i := slices.IndexFunc(v.Players, func(p game.PlayerView) bool { return p.ID == victim })
	if v.Players[i].Status != game.StatusEliminated {
		t.Fatalf("%s is %q, want eliminated", victim, v.Players[i].Status)
	}
	if r.member(victim) == nil {
		t.Fatalf("%s lost their seat in the room after being voted out", victim)
	}
}
