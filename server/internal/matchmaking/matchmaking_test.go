package matchmaking

import (
	"slices"
	"testing"
	"time"
)

var t0 = time.Date(2026, 9, 15, 12, 0, 0, 0, time.UTC)

func at(s int) time.Time { return t0.Add(time.Duration(s) * time.Second) }

func TestStartRules(t *testing.T) {
	var timers Timers
	check := func(step string, status Status, start time.Time) {
		t.Helper()
		if timers.Status() != status || !timers.StartAt().Equal(start) {
			t.Fatalf("%s: status %s start %v, want %s %v", step, timers.Status(), timers.StartAt(), status, start)
		}
	}

	timers.Update(3, at(10))
	check("3 players search", StatusSearching, time.Time{})

	timers.Update(4, at(40))
	check("4th player starts a 30-second wait", StatusWaitingForMore, at(70))

	timers.Update(5, at(45))
	check("a 5th player keeps the wait", StatusWaitingForMore, at(70))

	timers.Update(6, at(50))
	check("6th player starts a 5-second countdown", StatusCountdown, at(55))

	timers.Update(5, at(52))
	check("a cancel keeps the countdown while 4 remain", StatusCountdown, at(55))

	timers.Update(8, at(53))
	check("8 players still wait for the countdown", StatusCountdown, at(55))

	timers.Update(3, at(54))
	check("below 4 stops everything", StatusSearching, time.Time{})

	timers.Update(4, at(90))
	check("4 again starts a fresh 30 seconds", StatusWaitingForMore, at(120))
}

func TestCountdownNeverDelaysAnEarlierWaitEnd(t *testing.T) {
	var timers Timers
	timers.Update(4, at(0))
	timers.Update(6, at(28)) // the wait ends at 30, before the countdown at 33
	if !timers.StartAt().Equal(at(30)) {
		t.Fatalf("start %v, want %v", timers.StartAt(), at(30))
	}
}

func TestShared(t *testing.T) {
	if got := Shared([]string{"food", "film_tv", "sports"}, []string{"sports", "food"}); !slices.Equal(got, []string{"food", "sports"}) {
		t.Fatalf("Shared = %v", got)
	}
	if got := Shared([]string{"food"}, []string{"film_tv"}); got != nil {
		t.Fatalf("no overlap = %v", got)
	}
}
