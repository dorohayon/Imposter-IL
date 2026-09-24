package monetization

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"math/big"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

var now = time.Date(2026, 9, 23, 12, 0, 0, 0, time.UTC)

func TestDefaultConfig(t *testing.T) {
	c := Default()
	if err := c.validate(); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(c.FreeCategoryIDs, []string{"food", "animals", "places"}) {
		t.Fatalf("free categories = %v, the design names food, animals and places", c.FreeCategoryIDs)
	}
	if c.ServerEnforcement {
		t.Fatal("enforcement must stay off until the store verifiers are configured")
	}
	// Release builds show no ads without units, so both platforms need both.
	for _, platform := range []string{"android", "ios"} {
		u := c.Ads.Units[platform]
		if !strings.HasPrefix(u.Banner, "ca-app-pub-9035143252838544/") ||
			!strings.HasPrefix(u.Interstitial, "ca-app-pub-9035143252838544/") || u.Banner == u.Interstitial {
			t.Errorf("%s units = %+v", platform, u)
		}
	}
}

func TestParse(t *testing.T) {
	c, err := Parse([]byte(`{"freeCategoryIds":["sports"],"ads":{"interstitialMinIntervalSeconds":120}}`))
	if err != nil {
		t.Fatal(err)
	}
	// An override names only what it changes; the rest keeps its default.
	if !slices.Equal(c.FreeCategoryIDs, []string{"sports"}) || c.Ads.InterstitialMinIntervalSeconds != 120 ||
		c.Products.PremiumMonthly != "premium_monthly" || !c.Ads.Enabled {
		t.Fatalf("parsed %+v", c)
	}
	for name, bad := range map[string]string{
		"misspelt key":      `{"freeCategories":["food"]}`,
		"unknown category":  `{"freeCategoryIds":["cars"]}`,
		"no free category":  `{"freeCategoryIds":[]}`,
		"same premium ids":  `{"products":{"categoryPrefix":"c_","premiumMonthly":"p","premiumLifetime":"p"}}`,
		"bad rating":        `{"ads":{"maxAdContentRating":"R"}}`,
		"negative interval": `{"ads":{"interstitialMinIntervalSeconds":-1}}`,
		"not json":          `{`,
		"too large":         `{"x":"` + strings.Repeat("a", maxConfigBytes) + `"}`,
	} {
		if _, err := Parse([]byte(bad)); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}
}

func TestAllowedAndGrant(t *testing.T) {
	c := Default()
	free := Entitlements{}
	if !c.Allowed(free, []string{"food", "places"}, now) || c.Allowed(free, []string{"food", "sports"}, now) {
		t.Fatal("a free player gets exactly the free categories")
	}

	sports := c.Grant(free, Grant{ProductID: "category_sports"}, now)
	if !c.Allowed(sports, []string{"sports", "food"}, now) || c.Allowed(sports, []string{"objects"}, now) {
		t.Fatal("a category purchase unlocks that category only")
	}
	if sports.Premium(now) {
		t.Fatal("a category purchase is not Premium, so ads stay")
	}

	monthly := c.Grant(free, Grant{ProductID: "premium_monthly", Expires: now.Add(time.Hour)}, now)
	if !monthly.Premium(now) || !c.Allowed(monthly, []string{"objects", "sports"}, now) {
		t.Fatal("active monthly Premium unlocks everything")
	}
	if monthly.Premium(now.Add(2*time.Hour)) || c.Allowed(monthly, []string{"sports"}, now.Add(2*time.Hour)) {
		t.Fatal("monthly Premium lapses when the period ends")
	}
	lapsed := c.Grant(free, Grant{ProductID: "premium_monthly", Expires: now.Add(-time.Hour)}, now)
	if lapsed.Premium(now) {
		t.Fatal("an ended period grants nothing")
	}

	lifetime := c.Grant(free, Grant{ProductID: "premium_lifetime"}, now)
	if !lifetime.Premium(now.AddDate(50, 0, 0)) {
		t.Fatal("lifetime Premium never lapses")
	}

	for _, unknown := range []string{"category_cars", "category_", "coins_100", ""} {
		if got := c.Grant(free, Grant{ProductID: unknown}, now); got.Premium(now) || got.Categories != nil {
			t.Errorf("%q granted %+v", unknown, got)
		}
		if c.Known(unknown) {
			t.Errorf("%q is known", unknown)
		}
	}
	for _, known := range []string{"category_sports", "premium_monthly", "premium_lifetime"} {
		if !c.Known(known) {
			t.Errorf("%q is unknown", known)
		}
	}
}

// ---- Apple ------------------------------------------------------------------

type applePKI struct {
	roots        *x509.CertPool
	chain        []string // x5c: leaf, intermediate, root
	leafKey      *ecdsa.PrivateKey
	intermediate *x509.Certificate
	intKey       *ecdsa.PrivateKey
}

func newCert(t *testing.T, tmpl, parent *x509.Certificate, pub any, signer *ecdsa.PrivateKey) *x509.Certificate {
	t.Helper()
	der, err := x509.CreateCertificate(rand.Reader, tmpl, parent, pub, signer)
	if err != nil {
		t.Fatal(err)
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	return cert
}

func key(t *testing.T) *ecdsa.PrivateKey {
	t.Helper()
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return k
}

func appleExtension(oid []int) pkix.Extension {
	return pkix.Extension{Id: oid, Value: []byte{0x05, 0x00}} // ASN.1 NULL, as Apple does
}

// newApplePKI mirrors Apple's chain: a root, an intermediate and a leaf, the
// last two carrying Apple's receipt-signing extensions.
func newApplePKI(t *testing.T) applePKI {
	t.Helper()
	valid := func(serial int64) *x509.Certificate {
		return &x509.Certificate{
			SerialNumber: big.NewInt(serial),
			NotBefore:    now.AddDate(-1, 0, 0),
			NotAfter:     now.AddDate(1, 0, 0),
		}
	}
	rootKey, intKey, leafKey := key(t), key(t), key(t)
	rootTmpl := valid(1)
	rootTmpl.Subject = pkix.Name{CommonName: "Test Root"}
	rootTmpl.IsCA, rootTmpl.BasicConstraintsValid = true, true
	rootTmpl.KeyUsage = x509.KeyUsageCertSign
	root := newCert(t, rootTmpl, rootTmpl, &rootKey.PublicKey, rootKey)

	intTmpl := valid(2)
	intTmpl.Subject = pkix.Name{CommonName: "Test Intermediate"}
	intTmpl.IsCA, intTmpl.BasicConstraintsValid = true, true
	intTmpl.KeyUsage = x509.KeyUsageCertSign
	intTmpl.ExtraExtensions = []pkix.Extension{appleExtension(oidAppleIntermediate)}
	intermediate := newCert(t, intTmpl, root, &intKey.PublicKey, rootKey)

	leafTmpl := valid(3)
	leafTmpl.Subject = pkix.Name{CommonName: "Test Leaf"}
	leafTmpl.ExtraExtensions = []pkix.Extension{appleExtension(oidAppleReceiptLeaf)}
	leaf := newCert(t, leafTmpl, intermediate, &leafKey.PublicKey, intKey)

	roots := x509.NewCertPool()
	roots.AddCert(root)
	chain := []string{}
	for _, c := range []*x509.Certificate{leaf, intermediate, root} {
		chain = append(chain, base64.StdEncoding.EncodeToString(c.Raw))
	}
	return applePKI{roots: roots, chain: chain, leafKey: leafKey, intermediate: intermediate, intKey: intKey}
}

func (p applePKI) sign(t *testing.T, payload map[string]any) string {
	t.Helper()
	enc := base64.RawURLEncoding
	header, _ := json.Marshal(map[string]any{"alg": "ES256", "x5c": p.chain})
	body, _ := json.Marshal(payload)
	unsigned := enc.EncodeToString(header) + "." + enc.EncodeToString(body)
	digest := sha256.Sum256([]byte(unsigned))
	r, s, err := ecdsa.Sign(rand.Reader, p.leafKey, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return unsigned + "." + enc.EncodeToString(sig)
}

func transaction(product string, extra map[string]any) map[string]any {
	tx := map[string]any{
		"environment": "Production",
		"bundleId":    "com.imposter.il",
		"productId":   product,
		"signedDate":  now.Add(-time.Minute).UnixMilli(),
	}
	for k, v := range extra {
		tx[k] = v
	}
	return tx
}

func TestAppleVerifier(t *testing.T) {
	pki := newApplePKI(t)
	v := AppleVerifier{BundleID: "com.imposter.il", Roots: pki.roots}
	ctx := context.Background()

	got, err := v.Verify(ctx, "category_sports", pki.sign(t, transaction("category_sports", nil)), false, now)
	if err != nil || got.ProductID != "category_sports" || !got.Expires.IsZero() {
		t.Fatalf("non-consumable: %+v %v", got, err)
	}

	expires := now.Add(20 * 24 * time.Hour).Truncate(time.Millisecond)
	got, err = v.Verify(ctx, "premium_monthly",
		pki.sign(t, transaction("premium_monthly", map[string]any{"expiresDate": expires.UnixMilli()})), true, now)
	if err != nil || !got.Expires.Equal(expires) {
		t.Fatalf("subscription: %+v %v", got, err)
	}

	// App Review buys in Sandbox against the production server.
	if _, err := v.Verify(ctx, "category_sports",
		pki.sign(t, transaction("category_sports", map[string]any{"environment": "Sandbox"})), false, now); err != nil {
		t.Fatalf("sandbox: %v", err)
	}

	// A lifetime purchase signed long ago is still good after the leaf
	// expired: the chain is checked at signing time.
	old := transaction("premium_lifetime", map[string]any{"signedDate": now.AddDate(0, -6, 0).UnixMilli()})
	if _, err := v.Verify(ctx, "premium_lifetime", pki.sign(t, old), false, now.AddDate(5, 0, 0)); err != nil {
		t.Fatalf("old lifetime purchase: %v", err)
	}

	valid := pki.sign(t, transaction("category_sports", nil))
	parts := strings.Split(valid, ".")
	forged, _ := json.Marshal(transaction("premium_lifetime", nil))
	tampered := parts[0] + "." + base64.RawURLEncoding.EncodeToString(forged) + "." + parts[2]

	stranger := newApplePKI(t) // a chain that does not reach our root
	// The same trusted chain, but a leaf without Apple's receipt extension.
	noLeafOID := pki
	noLeafOID.leafKey = key(t)
	bare := newCert(t, &x509.Certificate{
		SerialNumber: big.NewInt(4), NotBefore: now.AddDate(-1, 0, 0), NotAfter: now.AddDate(1, 0, 0),
	}, pki.intermediate, &noLeafOID.leafKey.PublicKey, pki.intKey)
	noLeafOID.chain = append([]string{base64.StdEncoding.EncodeToString(bare.Raw)}, pki.chain[1:]...)
	noLeafV := v

	for name, c := range map[string]struct {
		v       AppleVerifier
		product string
		jws     string
	}{
		"tampered payload":      {v, "premium_lifetime", tampered},
		"another app":           {v, "category_sports", pki.sign(t, transaction("category_sports", map[string]any{"bundleId": "com.other"}))},
		"another product":       {v, "premium_lifetime", valid},
		"refunded":              {v, "category_sports", pki.sign(t, transaction("category_sports", map[string]any{"revocationDate": now.UnixMilli()}))},
		"period over":           {v, "premium_monthly", pki.sign(t, transaction("premium_monthly", map[string]any{"expiresDate": now.Add(-time.Second).UnixMilli()}))},
		"untrusted chain":       {v, "category_sports", stranger.sign(t, transaction("category_sports", nil))},
		"leaf without apple id": {noLeafV, "category_sports", noLeafOID.sign(t, transaction("category_sports", nil))},
		"local StoreKit test":   {v, "category_sports", pki.sign(t, transaction("category_sports", map[string]any{"environment": "Xcode"}))},
		"no environment":        {v, "category_sports", pki.sign(t, transaction("category_sports", map[string]any{"environment": ""}))},
		"not a jws":             {v, "category_sports", "abc"},
		"empty":                 {v, "category_sports", ""},
		"unsigned alg":          {v, "category_sports", swapHeader(t, valid, map[string]any{"alg": "none", "x5c": pki.chain})},
		"no chain":              {v, "category_sports", swapHeader(t, valid, map[string]any{"alg": "ES256"})},
	} {
		if _, err := c.v.Verify(ctx, c.product, c.jws, false, now); !errors.Is(err, ErrInvalidProof) {
			t.Errorf("%s: err = %v, want ErrInvalidProof", name, err)
		}
	}
}

func swapHeader(t *testing.T, jws string, header map[string]any) string {
	t.Helper()
	raw, _ := json.Marshal(header)
	parts := strings.Split(jws, ".")
	return base64.RawURLEncoding.EncodeToString(raw) + "." + parts[1] + "." + parts[2]
}

func TestAppleRootParses(t *testing.T) {
	v := NewAppleVerifier("com.imposter.il")
	if v.Roots == nil {
		t.Fatal("no roots")
	}
	// A real Apple root rejects our test chain.
	pki := newApplePKI(t)
	if _, err := v.Verify(context.Background(), "category_sports", pki.sign(t, transaction("category_sports", nil)), false, now); !errors.Is(err, ErrInvalidProof) {
		t.Fatalf("test chain accepted by the Apple root: %v", err)
	}
}

// ---- Google -----------------------------------------------------------------

func googleVerifier(t *testing.T, handler http.HandlerFunc) (*GoogleVerifier, *atomic.Int32) {
	t.Helper()
	rsaKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, _ := x509.MarshalPKCS8PrivateKey(rsaKey)
	tokens := &atomic.Int32{}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /token", func(w http.ResponseWriter, r *http.Request) {
		tokens.Add(1)
		if r.FormValue("grant_type") != "urn:ietf:params:oauth:grant-type:jwt-bearer" || r.FormValue("assertion") == "" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		_, _ = w.Write([]byte(`{"access_token":"at-1","expires_in":3600}`))
	})
	mux.HandleFunc("/androidpublisher/", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer at-1" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		handler(w, r)
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)

	sa, _ := json.Marshal(map[string]string{
		"client_email": "verifier@example.iam.gserviceaccount.com",
		"private_key":  string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})),
		"token_uri":    srv.URL + "/token",
	})
	v, err := NewGoogleVerifier("com.imposter.il", sa)
	if err != nil {
		t.Fatal(err)
	}
	v.BaseURL = srv.URL
	return v, tokens
}

func TestGoogleVerifierProducts(t *testing.T) {
	v, tokens := googleVerifier(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/androidpublisher/v3/applications/com.imposter.il/purchases/products/category_sports/tokens/good":
			_, _ = w.Write([]byte(`{"purchaseState":0}`))
		case "/androidpublisher/v3/applications/com.imposter.il/purchases/products/category_sports/tokens/refunded":
			_, _ = w.Write([]byte(`{"purchaseState":1}`))
		case "/androidpublisher/v3/applications/com.imposter.il/purchases/products/category_sports/tokens/pending":
			_, _ = w.Write([]byte(`{"purchaseState":2}`))
		case "/androidpublisher/v3/applications/com.imposter.il/purchases/products/category_sports/tokens/down":
			w.WriteHeader(http.StatusServiceUnavailable)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	})
	ctx := context.Background()
	got, err := v.Verify(ctx, "category_sports", "good", false, now)
	if err != nil || got.ProductID != "category_sports" || !got.Expires.IsZero() {
		t.Fatalf("purchased: %+v %v", got, err)
	}
	for token, want := range map[string]error{
		"refunded": ErrInvalidProof,
		"pending":  ErrInvalidProof,
		"unknown":  ErrInvalidProof,
		"":         ErrInvalidProof,
		"down":     ErrUnavailable,
	} {
		if _, err := v.Verify(ctx, "category_sports", token, false, now); !errors.Is(err, want) {
			t.Errorf("%q: err = %v, want %v", token, err, want)
		}
	}
	if n := tokens.Load(); n != 1 {
		t.Fatalf("OAuth token fetched %d times, want once and reused", n)
	}
}

func TestGoogleVerifierSubscriptions(t *testing.T) {
	expiry := now.Add(10 * 24 * time.Hour).Truncate(time.Second)
	body := func(state string, at time.Time) string {
		return `{"subscriptionState":"` + state + `","lineItems":[{"productId":"premium_monthly","expiryTime":"` +
			at.Format(time.RFC3339) + `"}]}`
	}
	responses := map[string]string{
		"active":   body("SUBSCRIPTION_STATE_ACTIVE", expiry),
		"grace":    body("SUBSCRIPTION_STATE_IN_GRACE_PERIOD", expiry),
		"canceled": body("SUBSCRIPTION_STATE_CANCELED", expiry),
		"hold":     body("SUBSCRIPTION_STATE_ON_HOLD", expiry),
		"expired":  body("SUBSCRIPTION_STATE_EXPIRED", now.Add(-time.Hour)),
		"revoked":  body("SUBSCRIPTION_STATE_REVOKED", expiry),
		"stale":    body("SUBSCRIPTION_STATE_CANCELED", now.Add(-time.Hour)),
	}
	v, _ := googleVerifier(t, func(w http.ResponseWriter, r *http.Request) {
		token, ok := strings.CutPrefix(r.URL.Path, "/androidpublisher/v3/applications/com.imposter.il/purchases/subscriptionsv2/tokens/")
		if !ok || responses[token] == "" {
			w.WriteHeader(http.StatusGone)
			return
		}
		_, _ = w.Write([]byte(responses[token]))
	})
	ctx := context.Background()
	// Cancelled keeps access until the paid period ends.
	for _, token := range []string{"active", "grace", "canceled"} {
		got, err := v.Verify(ctx, "premium_monthly", token, true, now)
		if err != nil || !got.Expires.Equal(expiry) {
			t.Errorf("%s: %+v %v", token, got, err)
		}
	}
	for _, token := range []string{"hold", "expired", "revoked", "stale", "gone"} {
		if _, err := v.Verify(ctx, "premium_monthly", token, true, now); !errors.Is(err, ErrInvalidProof) {
			t.Errorf("%s: err = %v, want ErrInvalidProof", token, err)
		}
	}
}

func TestGoogleVerifierBadServiceAccount(t *testing.T) {
	for name, sa := range map[string]string{
		"not json":   `{`,
		"no key":     `{"client_email":"a","token_uri":"b"}`,
		"no email":   `{"private_key":"-----BEGIN PRIVATE KEY-----\nAA==\n-----END PRIVATE KEY-----\n","token_uri":"b"}`,
		"broken key": `{"client_email":"a","token_uri":"b","private_key":"-----BEGIN PRIVATE KEY-----\nAA==\n-----END PRIVATE KEY-----\n"}`,
	} {
		if _, err := NewGoogleVerifier("com.imposter.il", []byte(sa)); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}
}
