package devpolicy

import "testing"

func TestPolicy(t *testing.T) {
	p := Policy()
	if p.HintInappropriate("anything") || !p.ValidReaction("laugh") || p.ValidReaction("🔥") {
		t.Fatal("unexpected dev policy")
	}
}
