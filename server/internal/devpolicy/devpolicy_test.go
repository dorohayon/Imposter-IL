package devpolicy

import (
	"strings"
	"testing"
)

func TestPolicy(t *testing.T) {
	p := Policy()
	if p.HintInappropriate("anything") || !p.ValidReaction("😂") || p.ValidReaction(" ") || p.ValidReaction(strings.Repeat("a", 65)) {
		t.Fatal("unexpected dev policy")
	}
}
