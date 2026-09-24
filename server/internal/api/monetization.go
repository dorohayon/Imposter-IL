package api

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/monetization"
)

// Monetization endpoints (docs/monetization.md, docs/protocol.md).
//
// GET /v1/config is public: the app needs it before onboarding and in
// one-device play. POST /v1/entitlements takes the store's proofs of what this
// device owns, verifies them outside the server lock (Google's check is a
// network call) and replaces the session's entitlements with the result.

// Each proof can be a call to the Play Developer API, so syncs are limited per
// session, which is what a player sees, and more loosely per IP, which is
// what bounds abuse. A carrier NAT puts many players behind one address, so
// the IP limit alone would refuse real players at app launch.
const (
	maxProofs               = 20
	entitlementsPerMin      = 10 // per session
	entitlementsBurst       = 10
	entitlementsPerMinPerIP = 120
	entitlementsBurstPerIP  = 120
	verificationTimeout     = 15 * time.Second
)

var (
	errCategoryLocked       = apiError{http.StatusForbidden, "category_locked", "a chosen category is locked"}
	errVerificationDown     = apiError{http.StatusServiceUnavailable, "verification_unavailable", "the store could not be reached, try again later"}
	errInvalidEntitlementRq = apiError{http.StatusUnprocessableEntity, "invalid_purchases", "invalid purchases"}
)

// SetMonetization replaces the pricing model and the store verifiers, keyed
// by platform ("ios", "android"). A platform without a verifier has its
// proofs ignored.
func (s *Server) SetMonetization(cfg monetization.Config, verifiers map[string]monetization.Verifier) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.money, s.verifiers = cfg, verifiers
}

// categoriesAllowed is the one entitlement check, for online searches and
// private rooms alike. Called under s.mu.
func (s *Server) categoriesAllowed(sess *session, ids []string, now time.Time) bool {
	return !s.money.ServerEnforcement || s.money.Allowed(sess.entitlements, ids, now)
}

func (s *Server) getConfig(w http.ResponseWriter, _ *http.Request) {
	s.mu.Lock()
	cfg := s.money
	s.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]any{"monetization": cfg})
}

type purchaseProof struct {
	Platform         string `json:"platform"`
	ProductID        string `json:"productId"`
	VerificationData string `json:"verificationData"`
}

func (s *Server) syncEntitlements(w http.ResponseWriter, r *http.Request) {
	body, ok := readBody(w, r)
	var req struct {
		Purchases []purchaseProof `json:"purchases"`
	}
	if !ok || !decode(w, body, &req) {
		return
	}
	if len(req.Purchases) > maxProofs {
		writeError(w, errInvalidEntitlementRq)
		return
	}
	// A device owns at most one purchase of each product, so one proof per
	// product is all a request needs; the rest cannot multiply store calls.
	req.Purchases = oneProofPerProduct(req.Purchases)
	token, _ := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")

	s.mu.Lock()
	sess := s.sessions[token]
	now := s.now()
	if sess == nil {
		s.mu.Unlock()
		writeError(w, errSessionNotFound)
		return
	}
	if !s.entitlementLimit.allow(token, now) || !s.entitlementIPLimit.allow(s.clientIP(r), now) {
		s.metrics.rateLimited++
		s.mu.Unlock()
		writeError(w, errRateLimited)
		return
	}
	sess.lastSeen, sess.ip = now, s.clientIP(r)
	cfg, verifiers := s.money, s.verifiers
	s.mu.Unlock()

	ctx, cancel := context.WithTimeout(r.Context(), verificationTimeout)
	defer cancel()
	var granted monetization.Entitlements
	results := make([]map[string]string, 0, len(req.Purchases))
	for _, p := range req.Purchases {
		status := "rejected"
		verifier := verifiers[p.Platform]
		switch {
		case !cfg.Known(p.ProductID):
		case verifier == nil:
			status = "unverifiable"
		default:
			g, err := verifier.Verify(ctx, p.ProductID, p.VerificationData, p.ProductID == cfg.Products.PremiumMonthly, now)
			switch {
			case errors.Is(err, monetization.ErrUnavailable):
				// Taking a purchase away over an outage would be worse than
				// keeping yesterday's answer a little longer.
				writeError(w, errVerificationDown)
				return
			case err == nil:
				granted, status = cfg.Grant(granted, g, now), "granted"
			}
		}
		results = append(results, map[string]string{"productId": p.ProductID, "status": status})
	}

	s.mu.Lock()
	// The proofs are everything the store says this device owns now, so they
	// replace what the session had: a refund or a lapse takes effect here.
	if s.sessions[token] == sess {
		sess.entitlements = granted
	}
	s.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]any{
		"entitlements": entitlementsJSON(granted, now),
		"results":      results,
	})
}

func oneProofPerProduct(proofs []purchaseProof) []purchaseProof {
	seen := map[[2]string]bool{}
	out := proofs[:0]
	for _, p := range proofs {
		key := [2]string{p.Platform, p.ProductID}
		if !seen[key] {
			seen[key] = true
			out = append(out, p)
		}
	}
	return out
}

func entitlementsJSON(e monetization.Entitlements, now time.Time) map[string]any {
	out := map[string]any{
		"premium":     e.Premium(now),
		"lifetime":    e.Lifetime,
		"categoryIds": append([]string{}, e.Categories...),
	}
	if !e.PremiumUntil.IsZero() {
		out["premiumUntil"] = e.PremiumUntil.UTC().Format(time.RFC3339)
	}
	return out
}
