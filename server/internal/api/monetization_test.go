package api

import (
	"context"
	"fmt"
	"net/http"
	"slices"
	"testing"
	"time"

	"github.com/dorohayon/Imposter-IL/server/internal/monetization"
)

// fakeStore answers Verify from a table keyed by the proof's data.
type fakeStore map[string]fakeAnswer

type fakeAnswer struct {
	grant monetization.Grant
	err   error
}

func (f fakeStore) Verify(_ context.Context, productID, data string, _ bool, _ time.Time) (monetization.Grant, error) {
	a, ok := f[data]
	if !ok {
		return monetization.Grant{}, monetization.ErrInvalidProof
	}
	if a.err == nil && a.grant.ProductID != productID {
		return monetization.Grant{}, monetization.ErrInvalidProof
	}
	return a.grant, a.err
}

func enforcingClient(t *testing.T, store fakeStore) *client {
	c := newClient(t)
	cfg := monetization.Default()
	cfg.ServerEnforcement = true
	c.srv.SetMonetization(cfg, map[string]monetization.Verifier{"android": store})
	return c
}

func proof(platform, product, data string) map[string]string {
	return map[string]string{"platform": platform, "productId": product, "verificationData": data}
}

func (c *client) syncPurchases(token string, proofs ...map[string]string) (int, map[string]any) {
	c.t.Helper()
	return c.do("POST", "/v1/entitlements", token, map[string]any{"purchases": proofs})
}

func (c *client) roomWith(token string, categories ...string) (int, map[string]any) {
	c.t.Helper()
	return c.do("POST", "/v1/rooms", token, map[string]any{"maxPlayers": 4, "hintSeconds": 60, "categoryIds": categories})
}

func TestConfigIsPublic(t *testing.T) {
	c := newClient(t)
	status, body := c.do("GET", "/v1/config", "", nil)
	if status != http.StatusOK {
		t.Fatalf("GET /v1/config: %d %v", status, body)
	}
	cfg := body["monetization"].(map[string]any)
	free := cfg["freeCategoryIds"].([]any)
	if fmt.Sprint(free) != "[food places film_tv]" || cfg["serverEnforcement"] != false {
		t.Fatalf("config = %v", cfg)
	}
	products := cfg["products"].(map[string]any)
	if products["premiumMonthly"] != "premium_monthly" || products["premiumLifetime"] != "premium_lifetime" ||
		products["categoryPrefix"] != "category_" {
		t.Fatalf("products = %v", products)
	}
	// Prices come from the stores, localized; the server never names one.
	for _, key := range []string{"price", "prices"} {
		if _, ok := cfg[key]; ok {
			t.Fatalf("config carries %s", key)
		}
	}
}

func TestWithoutEnforcementEveryCategoryIsOpen(t *testing.T) {
	c := newClient(t)
	token, _ := c.session("דור")
	if status, body := c.roomWith(token, "sports", "gaming"); status != http.StatusCreated {
		t.Fatalf("create room: %d %v", status, body)
	}
}

func TestPrivateRoomHostNeedsTheCategories(t *testing.T) {
	store := fakeStore{
		"sports-token":  {grant: monetization.Grant{ProductID: "category_sports"}},
		"monthly-token": {grant: monetization.Grant{ProductID: "premium_monthly", Expires: t0.Add(time.Hour)}},
	}
	c := enforcingClient(t, store)
	token, _ := c.session("דור")

	status, body := c.roomWith(token, "food", "sports")
	c.wantError(http.StatusForbidden, "category_locked", status, body)
	if status, body := c.roomWith(token, "food", "film_tv", "places"); status != http.StatusCreated {
		t.Fatalf("free categories: %d %v", status, body)
	}

	status, body = c.syncPurchases(token, proof("android", "category_sports", "sports-token"))
	ent := body["entitlements"].(map[string]any)
	if status != http.StatusOK || ent["premium"] != false || fmt.Sprint(ent["categoryIds"]) != "[sports]" {
		t.Fatalf("sync: %d %v", status, body)
	}
	if status, body := c.roomWith(token, "sports", "food"); status != http.StatusCreated {
		t.Fatalf("bought category: %d %v", status, body)
	}
	status, body = c.roomWith(token, "gaming")
	c.wantError(http.StatusForbidden, "category_locked", status, body)

	// Monthly Premium opens everything while the period lasts.
	status, body = c.syncPurchases(token, proof("android", "premium_monthly", "monthly-token"))
	if status != http.StatusOK || body["entitlements"].(map[string]any)["premium"] != true {
		t.Fatalf("monthly: %d %v", status, body)
	}
	if status, body := c.roomWith(token, "gaming", "music"); status != http.StatusCreated {
		t.Fatalf("premium: %d %v", status, body)
	}
	c.advance(2 * time.Hour)
	status, body = c.roomWith(token, "gaming")
	c.wantError(http.StatusForbidden, "category_locked", status, body)
}

func TestEntitlementsAreReplacedBySync(t *testing.T) {
	store := fakeStore{"sports-token": {grant: monetization.Grant{ProductID: "category_sports"}}}
	c := enforcingClient(t, store)
	token, _ := c.session("דור")
	c.syncPurchases(token, proof("android", "category_sports", "sports-token"))
	if status, _ := c.roomWith(token, "sports"); status != http.StatusCreated {
		t.Fatal("bought category refused")
	}
	// A refund: the store no longer lists the purchase, so the device sends
	// what it has now — nothing.
	if status, body := c.syncPurchases(token); status != http.StatusOK {
		t.Fatalf("empty sync: %d %v", status, body)
	}
	status, body := c.roomWith(token, "sports")
	c.wantError(http.StatusForbidden, "category_locked", status, body)
}

func TestEntitlementProofResults(t *testing.T) {
	store := fakeStore{
		"good":    {grant: monetization.Grant{ProductID: "category_sports"}},
		"refund":  {err: monetization.ErrInvalidProof},
		"outage":  {err: monetization.ErrUnavailable},
		"sports2": {grant: monetization.Grant{ProductID: "category_sports"}},
	}
	c := enforcingClient(t, store)
	token, _ := c.session("דור")

	status, body := c.syncPurchases(token,
		proof("android", "category_sports", "good"),
		proof("android", "category_objects", "refund"),
		proof("android", "coins_100", "good"),          // not a product we sell
		proof("android", "category_places", "sports2"), // a proof for another product
		proof("ios", "premium_lifetime", "anything"),   // no Apple verifier configured
	)
	if status != http.StatusOK {
		t.Fatalf("sync: %d %v", status, body)
	}
	var got []string
	for _, r := range body["results"].([]any) {
		r := r.(map[string]any)
		got = append(got, r["productId"].(string)+":"+r["status"].(string))
	}
	want := []string{"category_sports:granted", "category_objects:rejected", "coins_100:rejected",
		"category_places:rejected", "premium_lifetime:unverifiable"}
	if !slices.Equal(got, want) {
		t.Fatalf("results = %v, want %v", got, want)
	}

	// An outage keeps what the player had instead of taking it away.
	status, body = c.syncPurchases(token, proof("android", "category_sports", "outage"))
	c.wantError(http.StatusServiceUnavailable, "verification_unavailable", status, body)
	if status, _ := c.roomWith(token, "sports"); status != http.StatusCreated {
		t.Fatal("an outage took away a verified purchase")
	}

	status, body = c.do("POST", "/v1/entitlements", "", map[string]any{"purchases": []any{}})
	c.wantError(http.StatusUnauthorized, "session_not_found", status, body)

	// The same product twice counts once: a request cannot multiply calls.
	status, body = c.syncPurchases(token,
		proof("android", "category_sports", "good"),
		proof("android", "category_sports", "good"),
		proof("android", "category_sports", "good"))
	if status != http.StatusOK || len(body["results"].([]any)) != 1 {
		t.Fatalf("duplicates: %d %v", status, body)
	}

	many := make([]map[string]string, maxProofs+1)
	for i := range many {
		many[i] = proof("android", "category_sports", "good")
	}
	status, body = c.syncPurchases(token, many...)
	c.wantError(http.StatusUnprocessableEntity, "invalid_purchases", status, body)
}

func TestEntitlementSyncIsRateLimited(t *testing.T) {
	c := enforcingClient(t, fakeStore{})
	token, _ := c.session("דור")
	for i := range entitlementsBurst {
		if status, body := c.syncPurchases(token); status != http.StatusOK {
			t.Fatalf("sync %d: %d %v", i, status, body)
		}
	}
	status, body := c.syncPurchases(token)
	c.wantError(http.StatusTooManyRequests, "rate_limited", status, body)

	// Another player behind the same address is not refused for it.
	other, _ := c.session("נועה")
	if status, body := c.syncPurchases(other); status != http.StatusOK {
		t.Fatalf("second session: %d %v", status, body)
	}
}

func TestOnlineSearchAndRoomSettingsNeedTheCategories(t *testing.T) {
	c := enforcingClient(t, fakeStore{"sports-token": {grant: monetization.Grant{ProductID: "category_sports"}}})
	token, _ := c.session("דור")
	w := c.dial(token)
	w.sessionState(func(s map[string]any) bool { return s["activity"] == "none" })

	wantReplyError(t, w.command("locked", "matchmaking.join", map[string]any{"categoryIds": []string{"food", "sports"}}), "category_locked")
	// Unknown ids keep their own error rather than looking locked.
	wantReplyError(t, w.command("bad", "matchmaking.join", map[string]any{"categoryIds": []string{"cars"}}), "invalid_categories")

	c.syncPurchases(token, proof("android", "category_sports", "sports-token"))
	wantOK(t, w.command("ok", "matchmaking.join", map[string]any{"categoryIds": []string{"food", "sports"}}))
	wantOK(t, w.command("cancel", "matchmaking.cancel", map[string]any{}))

	room := c.createRoom(token, 4) // film_tv, which is free
	settings := func(categories ...string) map[string]any {
		return map[string]any{"roomId": room["roomId"], "maxPlayers": 4, "hintSeconds": 60, "categoryIds": categories}
	}
	wantReplyError(t, w.command("settings-locked", "room.updateSettings", settings("gaming")), "category_locked")
	wantOK(t, w.command("settings-ok", "room.updateSettings", settings("sports", "film_tv")))
}

// "משחק נוסף" online searches again through joinSearch, so it is where a
// lapsed subscription has to stop: a player cannot keep a paid category by
// never leaving the result screen.
func TestLapsedEntitlementCannotSearchAgain(t *testing.T) {
	c := enforcingClient(t, fakeStore{
		"monthly-token": {grant: monetization.Grant{ProductID: "premium_monthly", Expires: t0.Add(time.Hour)}},
	})
	token, _ := c.session("דור")
	c.syncPurchases(token, proof("android", "premium_monthly", "monthly-token"))
	c.advance(2 * time.Hour)

	c.srv.mu.Lock()
	code := c.srv.joinSearch(c.srv.sessions[token], nil, []string{"sports"}, c.srv.now())
	c.srv.mu.Unlock()
	if code != "category_locked" {
		t.Fatalf("joinSearch after the period ended = %q, want category_locked", code)
	}
}

// A private room is checked again when its game starts: the host must own
// its categories, or the player who chose them must still be in the room and
// own them. A buyer's friends play while the buyer is there, not after.
func TestPrivateRoomStartNeedsAnOwnerInTheRoom(t *testing.T) {
	c := enforcingClient(t, fakeStore{
		"monthly-token": {grant: monetization.Grant{ProductID: "premium_monthly", Expires: t0.Add(time.Hour)}},
		"guest-token":   {grant: monetization.Grant{ProductID: "premium_monthly", Expires: t0.Add(3 * time.Hour)}},
	})
	hostToken, _ := c.session("מנהל")
	c.syncPurchases(hostToken, proof("android", "premium_monthly", "monthly-token"))
	status, body := c.do("POST", "/v1/rooms", hostToken, map[string]any{"maxPlayers": 8, "hintSeconds": 60, "categoryIds": []string{"sports"}})
	if status != http.StatusCreated {
		t.Fatalf("create room: %d %v", status, body)
	}
	room := body["room"].(map[string]any)
	roomID, code := room["roomId"].(string), room["code"].(string)
	host := &wsPlayer{token: hostToken, w: c.dial(hostToken)}
	var guests []*wsPlayer
	for i := range 4 {
		token, id := c.session(fmt.Sprintf("אורח%d", i+1))
		if status, body := c.join(token, code); status != http.StatusOK {
			t.Fatalf("join: %d %v", status, body)
		}
		guests = append(guests, &wsPlayer{id: id, token: token, w: c.dial(token)})
	}

	c.advance(2 * time.Hour) // the host's Premium lapses in the lobby
	wantReplyError(t, host.w.command("start", "room.start", map[string]any{"roomId": roomID}), "category_locked")

	// The buyer leaves; a free host inherits the room and cannot go on with
	// its paid categories.
	wantOK(t, host.w.command("leave", "room.leave", map[string]any{"roomId": roomID}))
	newHost := guests[0]
	newHost.w.roomState(func(r map[string]any) bool { return r["hostPlayerId"] == newHost.id })
	wantReplyError(t, newHost.w.command("free", "room.start", map[string]any{"roomId": roomID}), "category_locked")

	// A host who owns the categories can.
	c.syncPurchases(newHost.token, proof("android", "premium_monthly", "guest-token"))
	wantOK(t, newHost.w.command("owned", "room.start", map[string]any{"roomId": roomID}))
}

// A rewarded ad opens one category for the player's next game only, and the
// next unlock waits out the cooldown whatever the category.
func TestRewardedUnlockOpensOneGame(t *testing.T) {
	c := enforcingClient(t, fakeStore{})
	hostToken, _ := c.session("מנהל")
	unlock := func(category string) (int, map[string]any) {
		return c.do("POST", "/v1/rewarded-unlocks", hostToken, map[string]any{"categoryId": category})
	}
	if status, body := unlock("gaming"); status != http.StatusOK || body["categoryId"] != "gaming" {
		t.Fatalf("unlock: %d %v", status, body)
	}
	c.syncPurchases(hostToken) // a store sync replaces purchases, not the reward
	if status, body := unlock("sports"); status != http.StatusTooManyRequests ||
		body["error"].(map[string]any)["nextAvailableAt"] != t0.Add(monetization.RewardedCooldown).UTC().Format(time.RFC3339) {
		t.Fatalf("second unlock inside the cooldown: %d %v", status, body)
	}
	if status, body := unlock("gaming"); status != http.StatusOK {
		t.Fatalf("retrying the same unlock: %d %v", status, body)
	}

	status, body := c.roomWith(hostToken, "gaming")
	if status != http.StatusCreated {
		t.Fatalf("create room with the rewarded category: %d %v", status, body)
	}
	room := body["room"].(map[string]any)
	host := c.dial(hostToken)
	for i := range 3 {
		token, _ := c.session(fmt.Sprintf("אורח%d", i+1))
		if status, body := c.join(token, room["code"].(string)); status != http.StatusOK {
			t.Fatalf("join: %d %v", status, body)
		}
		c.dial(token)
	}
	wantOK(t, host.command("start", "room.start", map[string]any{"roomId": room["roomId"]}))

	c.srv.mu.Lock()
	open := c.srv.categoriesAllowed(c.srv.sessions[hostToken], []string{"gaming"}, c.srv.now())
	c.srv.mu.Unlock()
	if open {
		t.Fatal("the rewarded category is still open after the game started")
	}

	c.advance(monetization.RewardedCooldown)
	if status, body := unlock("sports"); status != http.StatusOK {
		t.Fatalf("unlock after the cooldown: %d %v", status, body)
	}
}

// Online "משחק נוסף" searches again without the category the ad opened.
func TestSpentRewardLeavesTheSearch(t *testing.T) {
	c := enforcingClient(t, fakeStore{})
	token, _ := c.session("דור")
	c.srv.mu.Lock()
	defer c.srv.mu.Unlock()
	sess := c.srv.sessions[token]
	sess.rewardCategory, sess.searchCategories = "gaming", []string{"food", "gaming"}
	c.srv.useReward(sess, c.srv.now())
	if sess.rewardCategory != "" || !slices.Equal(sess.searchCategories, []string{"food"}) {
		t.Fatalf("after the game: reward %q, search %v", sess.rewardCategory, sess.searchCategories)
	}
}
