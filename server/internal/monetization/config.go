// Package monetization holds the remotely configurable pricing model and the
// category entitlements it grants (docs/monetization.md).
//
// Three configured categories are free. Every other category is visible but
// locked until the player owns it, either on its own or through Premium
// (monthly while active, or lifetime). Premium also removes ads; a single
// category purchase does not.
//
// Nothing is stored: there are no accounts and no database. The app sends the
// store's signed proofs of what it owns, the server verifies them and keeps
// the result on the in-memory session until it expires.
package monetization

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/content"
)

// Config is served as-is at GET /v1/config, so the app changes behaviour
// without a release. Prices are deliberately absent: the app shows the
// store's localized ones.
type Config struct {
	// FreeCategoryIDs are open to everyone. Every other category is locked.
	FreeCategoryIDs []string `json:"freeCategoryIds"`
	Products        Products `json:"products"`
	// PurchasesEnabled hides the purchase popup's buy buttons when false, for
	// example during a store outage. Restore still works.
	PurchasesEnabled bool `json:"purchasesEnabled"`
	// ServerEnforcement makes the server refuse locked categories in online
	// searches and private rooms. Turn it on only once the store verifiers are
	// configured, or paying players are refused too.
	ServerEnforcement bool `json:"serverEnforcement"`
	Ads               Ads  `json:"ads"`
}

// Products are the store product ids. A category's product id is
// CategoryPrefix followed by the category id, so a new category needs a store
// product but no configuration change.
type Products struct {
	CategoryPrefix  string `json:"categoryPrefix"`
	PremiumMonthly  string `json:"premiumMonthly"`
	PremiumLifetime string `json:"premiumLifetime"`
}

type Ads struct {
	Enabled bool `json:"enabled"`
	// BannerPlacements are the screens that show the adaptive banner. The
	// app only knows the non-game screens the design allows, so a name
	// outside that list does nothing.
	BannerPlacements    []string `json:"bannerPlacements"`
	InterstitialEnabled bool     `json:"interstitialEnabled"`
	// InterstitialMinIntervalSeconds spaces out interstitials. Zero shows one
	// after every completed match.
	InterstitialMinIntervalSeconds int `json:"interstitialMinIntervalSeconds"`
	// MaxAdContentRating is AdMob's G, PG, T or MA.
	MaxAdContentRating string `json:"maxAdContentRating"`
	// Units are the AdMob ad unit ids per platform ("android", "ios"). Release
	// builds show no ads without them; debug builds always use Google's test
	// units. An override replaces the whole map.
	Units map[string]AdUnits `json:"units"`
}

type AdUnits struct {
	Banner       string `json:"banner"`
	Interstitial string `json:"interstitial"`
}

// BannerPlacements lists the screens the design allows a banner on
// (design/claude/Imposter IL Monetization.dc.html): home, categories, the
// search, private room screens, profile, settings, how to play and the
// one-device setup. Never game, result, error or first-run screens.
var BannerPlacements = []string{
	"home", "categories", "search", "friends", "create_room", "join_room",
	"lobby", "profile", "settings", "how_to_play", "local_players", "local_rules",
}

// Default is the approved model: food, world places and film/TV are free.
func Default() Config {
	return Config{
		FreeCategoryIDs: []string{"food", "places", "film_tv"},
		Products: Products{
			CategoryPrefix:  "category_",
			PremiumMonthly:  "premium_monthly",
			PremiumLifetime: "premium_lifetime",
		},
		PurchasesEnabled: true,
		Ads: Ads{
			Enabled:             true,
			BannerPlacements:    slices.Clone(BannerPlacements),
			InterstitialEnabled: true,
			MaxAdContentRating:  "PG",
			// The AdMob units (publisher pub-9035143252838544). Not secrets:
			// every build that shows an ad carries them.
			Units: map[string]AdUnits{
				"android": {
					Banner:       "ca-app-pub-9035143252838544/5555882846",
					Interstitial: "ca-app-pub-9035143252838544/5751238243",
				},
				"ios": {
					Banner:       "ca-app-pub-9035143252838544/4438156576",
					Interstitial: "ca-app-pub-9035143252838544/8466874805",
				},
			},
		},
	}
}

const maxConfigBytes = 16 << 10

// Parse reads the operator's JSON config (MONETIZATION_CONFIG) over the
// defaults, so an override names only what it changes. A misspelt key is an
// error rather than a silently ignored setting, and the result is validated
// before anything uses it.
func Parse(data []byte) (Config, error) {
	if len(data) > maxConfigBytes {
		return Config{}, errors.New("monetization config: larger than 16 KiB")
	}
	c := Default()
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&c); err != nil {
		return Config{}, fmt.Errorf("monetization config: %w", err)
	}
	return c, c.validate()
}

func (c Config) validate() error {
	switch {
	case len(c.FreeCategoryIDs) == 0 || !content.ValidIDs(c.FreeCategoryIDs):
		return errors.New("monetization config: freeCategoryIds must name known categories")
	case c.Products.CategoryPrefix == "" || c.Products.PremiumMonthly == "" || c.Products.PremiumLifetime == "":
		return errors.New("monetization config: every product id is required")
	case c.Products.PremiumMonthly == c.Products.PremiumLifetime:
		return errors.New("monetization config: premium product ids must differ")
	case !slices.Contains([]string{"G", "PG", "T", "MA"}, c.Ads.MaxAdContentRating):
		return errors.New("monetization config: maxAdContentRating must be G, PG, T or MA")
	case c.Ads.InterstitialMinIntervalSeconds < 0:
		return errors.New("monetization config: interstitialMinIntervalSeconds cannot be negative")
	}
	return nil
}

// Entitlements are what one player may use, from verified store proofs.
type Entitlements struct {
	// PremiumUntil is when monthly Premium lapses. Zero means no subscription.
	PremiumUntil time.Time
	Lifetime     bool
	Categories   []string // bought one at a time
}

// Premium reports whether all categories are open and ads are off.
func (e Entitlements) Premium(now time.Time) bool {
	return e.Lifetime || now.Before(e.PremiumUntil)
}

// Allowed reports whether a player with e may choose every one of ids.
func (c Config) Allowed(e Entitlements, ids []string, now time.Time) bool {
	if e.Premium(now) {
		return true
	}
	for _, id := range ids {
		if !slices.Contains(c.FreeCategoryIDs, id) && !slices.Contains(e.Categories, id) {
			return false
		}
	}
	return true
}

// Grant adds one verified purchase to e. An unknown product grants nothing
// rather than failing the rest.
func (c Config) Grant(e Entitlements, g Grant, now time.Time) Entitlements {
	switch g.ProductID {
	case c.Products.PremiumLifetime:
		e.Lifetime = true
	case c.Products.PremiumMonthly:
		if g.Expires.After(now) && g.Expires.After(e.PremiumUntil) {
			e.PremiumUntil = g.Expires
		}
	default:
		id, ok := strings.CutPrefix(g.ProductID, c.Products.CategoryPrefix)
		if ok && content.ValidIDs([]string{id}) && !slices.Contains(e.Categories, id) {
			e.Categories = append(e.Categories, id)
		}
	}
	return e
}
