package monetization

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	androidPublisherScope = "https://www.googleapis.com/auth/androidpublisher"
	androidPublisherAPI   = "https://androidpublisher.googleapis.com"
	maxGoogleResponse     = 1 << 20
)

// GoogleVerifier checks Play purchase tokens with the Play Developer API,
// authenticated as a service account that has "View financial data" in the
// Play Console. Only the standard library: the OAuth exchange is one signed
// JWT.
type GoogleVerifier struct {
	PackageName string
	// BaseURL and TokenURL are the Google endpoints; tests point them at a
	// local server.
	BaseURL string
	Client  *http.Client

	email    string
	key      *rsa.PrivateKey
	tokenURL string

	mu      sync.Mutex
	token   string
	expires time.Time

	// Answers Play gave recently, so a device that sends the same proof on
	// every launch costs one API call per cacheTTL, not one per launch. An
	// outage is never cached.
	cacheMu sync.Mutex
	cache   map[string]cachedAnswer
	// calls bounds concurrent requests to Google across all players.
	calls chan struct{}
}

type cachedAnswer struct {
	grant Grant
	err   error
	at    time.Time
}

const (
	cacheTTL      = 10 * time.Minute
	cacheMax      = 10_000
	maxGoogleCall = 8
)

// NewGoogleVerifier reads a service account key file's JSON.
func NewGoogleVerifier(packageName string, serviceAccountJSON []byte) (*GoogleVerifier, error) {
	var sa struct {
		ClientEmail string `json:"client_email"`
		PrivateKey  string `json:"private_key"`
		TokenURI    string `json:"token_uri"`
	}
	if err := json.Unmarshal(serviceAccountJSON, &sa); err != nil {
		return nil, fmt.Errorf("google service account: %w", err)
	}
	block, _ := pem.Decode([]byte(sa.PrivateKey))
	if block == nil || sa.ClientEmail == "" || sa.TokenURI == "" {
		return nil, errors.New("google service account: client_email, private_key and token_uri are required")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("google service account: %w", err)
	}
	key, ok := parsed.(*rsa.PrivateKey)
	if !ok {
		return nil, errors.New("google service account: private_key is not RSA")
	}
	return &GoogleVerifier{
		PackageName: packageName,
		BaseURL:     androidPublisherAPI,
		Client:      &http.Client{Timeout: 10 * time.Second},
		email:       sa.ClientEmail,
		key:         key,
		tokenURL:    sa.TokenURI,
		calls:       make(chan struct{}, maxGoogleCall),
	}, nil
}

func (v *GoogleVerifier) Verify(ctx context.Context, productID, token string, subscription bool, now time.Time) (Grant, error) {
	if token == "" {
		return Grant{}, ErrInvalidProof
	}
	key := productID + "\x00" + token
	v.cacheMu.Lock()
	hit, ok := v.cache[key]
	v.cacheMu.Unlock()
	// A cached subscription period that has since ended is not reused.
	if ok && now.Sub(hit.at) < cacheTTL && (hit.grant.Expires.IsZero() || now.Before(hit.grant.Expires)) {
		return hit.grant, hit.err
	}
	grant, err := v.verify(ctx, productID, token, subscription, now)
	if !errors.Is(err, ErrUnavailable) {
		v.cacheMu.Lock()
		if v.cache == nil || len(v.cache) >= cacheMax {
			// ponytail: dropping the whole cache at the cap; an LRU if it
			// is ever hit in practice.
			v.cache = map[string]cachedAnswer{}
		}
		v.cache[key] = cachedAnswer{grant: grant, err: err, at: now}
		v.cacheMu.Unlock()
	}
	return grant, err
}

func (v *GoogleVerifier) verify(ctx context.Context, productID, token string, subscription bool, now time.Time) (Grant, error) {
	base := v.BaseURL + "/androidpublisher/v3/applications/" + url.PathEscape(v.PackageName) + "/purchases/"
	if subscription {
		var sub struct {
			SubscriptionState string `json:"subscriptionState"`
			LineItems         []struct {
				ProductID  string    `json:"productId"`
				ExpiryTime time.Time `json:"expiryTime"`
			} `json:"lineItems"`
		}
		if err := v.get(ctx, base+"subscriptionsv2/tokens/"+url.PathEscape(token), now, &sub); err != nil {
			return Grant{}, err
		}
		// Canceled keeps access until the period ends; on hold, paused,
		// expired and revoked do not (Play subscription lifecycle).
		switch sub.SubscriptionState {
		case "SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD", "SUBSCRIPTION_STATE_CANCELED":
		default:
			return Grant{}, ErrInvalidProof
		}
		var expires time.Time
		for _, item := range sub.LineItems {
			if item.ProductID == productID && item.ExpiryTime.After(expires) {
				expires = item.ExpiryTime
			}
		}
		if !now.Before(expires) {
			return Grant{}, ErrInvalidProof
		}
		return Grant{ProductID: productID, Expires: expires}, nil
	}
	var product struct {
		// 0 purchased, 1 canceled (includes refunds), 2 pending.
		PurchaseState int `json:"purchaseState"`
	}
	path := base + "products/" + url.PathEscape(productID) + "/tokens/" + url.PathEscape(token)
	if err := v.get(ctx, path, now, &product); err != nil {
		return Grant{}, err
	}
	if product.PurchaseState != 0 {
		return Grant{}, ErrInvalidProof
	}
	return Grant{ProductID: productID}, nil
}

// get calls the API. A token Play does not know is invalid; anything else
// going wrong is an outage, which must not cost a player their purchase.
func (v *GoogleVerifier) get(ctx context.Context, endpoint string, now time.Time, dst any) error {
	select {
	case v.calls <- struct{}{}:
		defer func() { <-v.calls }()
	case <-ctx.Done():
		return ErrUnavailable
	}
	access, err := v.accessToken(ctx, now)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return ErrUnavailable
	}
	req.Header.Set("Authorization", "Bearer "+access)
	res, err := v.Client.Do(req)
	if err != nil {
		return ErrUnavailable
	}
	defer func() { _ = res.Body.Close() }()
	body, err := io.ReadAll(io.LimitReader(res.Body, maxGoogleResponse))
	switch {
	case err != nil:
		return ErrUnavailable
	case res.StatusCode == http.StatusBadRequest, res.StatusCode == http.StatusNotFound, res.StatusCode == http.StatusGone:
		return ErrInvalidProof
	case res.StatusCode != http.StatusOK:
		return ErrUnavailable
	}
	if json.Unmarshal(body, dst) != nil {
		return ErrUnavailable
	}
	return nil
}

// accessToken exchanges a signed JWT for an OAuth token and reuses it until
// shortly before it expires.
func (v *GoogleVerifier) accessToken(ctx context.Context, now time.Time) (string, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if v.token != "" && now.Before(v.expires) {
		return v.token, nil
	}
	enc := base64.RawURLEncoding
	header := enc.EncodeToString([]byte(`{"alg":"RS256","typ":"JWT"}`))
	claims, err := json.Marshal(map[string]any{
		"iss": v.email, "scope": androidPublisherScope, "aud": v.tokenURL,
		"iat": now.Unix(), "exp": now.Add(time.Hour).Unix(),
	})
	if err != nil {
		return "", ErrUnavailable
	}
	unsigned := header + "." + enc.EncodeToString(claims)
	digest := sha256.Sum256([]byte(unsigned))
	sig, err := rsa.SignPKCS1v15(rand.Reader, v.key, crypto.SHA256, digest[:])
	if err != nil {
		return "", ErrUnavailable
	}
	form := url.Values{
		"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"},
		"assertion":  {unsigned + "." + enc.EncodeToString(sig)},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, v.tokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return "", ErrUnavailable
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, err := v.Client.Do(req)
	if err != nil {
		return "", ErrUnavailable
	}
	defer func() { _ = res.Body.Close() }()
	var out struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	body, err := io.ReadAll(io.LimitReader(res.Body, maxGoogleResponse))
	if err != nil || res.StatusCode != http.StatusOK || json.Unmarshal(body, &out) != nil || out.AccessToken == "" {
		return "", ErrUnavailable
	}
	v.token = out.AccessToken
	v.expires = now.Add(time.Duration(out.ExpiresIn)*time.Second - time.Minute)
	return v.token, nil
}
