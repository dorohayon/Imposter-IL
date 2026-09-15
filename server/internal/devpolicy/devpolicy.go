// Package devpolicy is a development-only stand-in for the content rules that
// are still undecided: the reactions list and the inappropriate-words
// dictionary (docs/open-decisions.md). cmd/server uses it only when
// IMPOSTER_DEV_POLICY=1, so no placeholder reaches production silently.
package devpolicy

import (
	"strings"

	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

// EnvVar enables this package in cmd/server when set to "1".
const EnvVar = "IMPOSTER_DEV_POLICY"

// Policy blocks no hint and accepts any short reaction id.
func Policy() game.Policy {
	return game.Policy{
		HintInappropriate: func(string) bool { return false },
		ValidReaction: func(id string) bool {
			return strings.TrimSpace(id) != "" && len(id) <= 64
		},
	}
}
