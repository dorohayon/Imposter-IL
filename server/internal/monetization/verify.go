package monetization

import (
	"context"
	"errors"
	"time"
)

// Grant is what one verified purchase is worth.
type Grant struct {
	ProductID string
	// Expires is when a subscription period ends; zero for a purchase that
	// does not expire. A lapsed, refunded or revoked purchase is an error
	// instead, so it never reaches Config.Grant.
	Expires time.Time
}

// Verifier checks one store's proof of purchase.
type Verifier interface {
	// Verify checks data for productID. subscription says which kind of
	// product it is, which Google needs to pick the endpoint.
	Verify(ctx context.Context, productID, data string, subscription bool, now time.Time) (Grant, error)
}

var (
	// ErrInvalidProof is a proof that is forged, for another app or product,
	// refunded, revoked or not paid for. It grants nothing.
	ErrInvalidProof = errors.New("monetization: invalid proof")
	// ErrUnavailable means the store could not be asked. The caller keeps
	// what the player had, rather than taking away a purchase over an outage.
	ErrUnavailable = errors.New("monetization: store unavailable")
)

// Known reports whether productID is one this config sells.
func (c Config) Known(productID string) bool {
	if productID == c.Products.PremiumMonthly || productID == c.Products.PremiumLifetime {
		return true
	}
	return c.Grant(Entitlements{}, Grant{ProductID: productID}, time.Time{}).Categories != nil
}
