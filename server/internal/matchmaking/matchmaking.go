// Package matchmaking holds the approved start rules for online games
// (docs/decisions.md). It only computes timers and grouping; the caller keeps
// the players and starts the game.
package matchmaking

import (
	"slices"
	"time"
)

const (
	MinPlayers       = 4
	CountdownPlayers = 6
	MaxPlayers       = 8

	// Wait starts when the 4th player is found; the game starts when it ends.
	Wait = 30 * time.Second
	// Countdown starts when the 6th player is found and ends the wait early.
	Countdown = 20 * time.Second
	// NoMatch is how long a player searches with fewer than 4 players found.
	NoMatch = 2 * time.Minute
)

type Status string

const (
	StatusSearching      Status = "searching"        // fewer than 4 players
	StatusWaitingForMore Status = "waiting_for_more" // 30-second wait
	StatusCountdown      Status = "countdown"        // 20 seconds to start
)

// Timers are the start timers of one forming game.
type Timers struct {
	WaitUntil      time.Time
	CountdownUntil time.Time
}

// Update applies the rules after the number of searching players changed:
// below 4 everything stops; reaching 4 starts a fresh 30-second wait; reaching
// 6 starts the 20-second countdown, which then keeps running even if players
// cancel, as long as at least 4 remain.
func (t *Timers) Update(players int, now time.Time) {
	if players < MinPlayers {
		*t = Timers{}
		return
	}
	if t.WaitUntil.IsZero() {
		t.WaitUntil = now.Add(Wait)
	}
	if players >= CountdownPlayers && t.CountdownUntil.IsZero() {
		t.CountdownUntil = now.Add(Countdown)
	}
}

// StartAt is when the game starts, or zero while fewer than 4 are found.
func (t Timers) StartAt() time.Time {
	if t.CountdownUntil.IsZero() || (!t.WaitUntil.IsZero() && t.WaitUntil.Before(t.CountdownUntil)) {
		return t.WaitUntil
	}
	return t.CountdownUntil
}

func (t Timers) Status() Status {
	switch {
	case t.WaitUntil.IsZero():
		return StatusSearching
	case !t.CountdownUntil.IsZero():
		return StatusCountdown
	}
	return StatusWaitingForMore
}

// Shared returns the categories two selections have in common, keeping the
// order of a. Players can share a game only when this is not empty.
func Shared(a, b []string) []string {
	var out []string
	for _, id := range a {
		if slices.Contains(b, id) {
			out = append(out, id)
		}
	}
	return out
}
