// Package devpolicy is a development-only stand-in for the inappropriate-words
// dictionary, which is still undecided (docs/open-decisions.md). cmd/server
// uses it only when IMPOSTER_DEV_POLICY=1, so no placeholder reaches
// production silently.
package devpolicy

import (
	"github.com/dorohayon/Imposter-IL/server/internal/content"
	"github.com/dorohayon/Imposter-IL/server/internal/game"
)

// EnvVar enables this package in cmd/server when set to "1".
const EnvVar = "IMPOSTER_DEV_POLICY"

// Policy blocks no hint as inappropriate and uses the approved reactions.
func Policy() game.Policy {
	return game.Policy{
		HintInappropriate: func(string) bool { return false },
		ValidReaction:     content.ValidReaction,
	}
}
