package monetization

import (
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// AppleRootG3 is Apple Root CA - G3, which signs every StoreKit 2 transaction
// (https://www.apple.com/certificateauthority/). SHA-256 fingerprint
// 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79.
const AppleRootG3 = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----
`

// Apple marks the certificates it uses for App Store receipts with these
// extensions; a chain to the root without them is some other Apple
// certificate (App Store Server Library, SignedDataVerifier).
var (
	oidAppleReceiptLeaf  = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 11, 1}
	oidAppleIntermediate = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 2, 1}
)

// AppleVerifier checks StoreKit 2 signed transactions (the JWS the app gets as
// serverVerificationData) offline, against Apple's root. No App Store Server
// API key is needed: the signature is the proof.
//
// Offline, a refund after the proof was signed is invisible: a client that
// keeps replaying the old JWS keeps the purchase. With API set, each proof is
// also looked up in the App Store Server API, which knows about refunds.
type AppleVerifier struct {
	BundleID string
	Roots    *x509.CertPool
	API      *AppleAPI // optional
}

// AppleAPI asks the App Store Server API whether a transaction was refunded
// or revoked after it was signed. It needs an In-App Purchase key from App
// Store Connect (Users and Access → Integrations).
type AppleAPI struct {
	IssuerID, KeyID string
	Key             *ecdsa.PrivateKey
	Client          *http.Client
	// BaseURL replaces both Apple hosts; tests point it at a local server.
	BaseURL string

	mu    sync.Mutex
	cache map[string]appleStatus // transaction id -> last answer
}

type appleStatus struct {
	revoked bool
	at      time.Time
}

// NewAppleAPI reads the In-App Purchase key file (.p8) contents.
func NewAppleAPI(issuerID, keyID string, p8 []byte) (*AppleAPI, error) {
	block, _ := pem.Decode(p8)
	if block == nil || issuerID == "" || keyID == "" {
		return nil, errors.New("apple api: issuer id, key id and a PEM private key are required")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("apple api: %w", err)
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, errors.New("apple api: private key is not EC")
	}
	return &AppleAPI{IssuerID: issuerID, KeyID: keyID, Key: key, Client: &http.Client{Timeout: 10 * time.Second}}, nil
}

// NewAppleVerifier trusts Apple Root CA - G3.
func NewAppleVerifier(bundleID string) AppleVerifier {
	roots := x509.NewCertPool()
	block, _ := pem.Decode([]byte(AppleRootG3))
	root, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		panic(err) // a constant; it parses or the binary is broken
	}
	roots.AddCert(root)
	return AppleVerifier{BundleID: bundleID, Roots: roots}
}

type appleTransaction struct {
	// Environment is "Production" or "Sandbox". Sandbox has to pass: App
	// Review buys in Sandbox against the production server, for every
	// release. The cost is that TestFlight testers' free purchases open
	// categories online too (docs/monetization.md). Anything else — a local
	// StoreKit test — is refused.
	Environment    string `json:"environment"`
	BundleID       string `json:"bundleId"`
	ProductID      string `json:"productId"`
	SignedDate     int64  `json:"signedDate"`
	ExpiresDate    int64  `json:"expiresDate"`
	RevocationDate int64  `json:"revocationDate"`
	TransactionID  string `json:"transactionId"`
}

func (v AppleVerifier) Verify(ctx context.Context, productID, data string, _ bool, now time.Time) (Grant, error) {
	tx, err := v.verifyJWS(data)
	if err != nil {
		return Grant{}, err
	}
	switch {
	case tx.Environment != "Production" && tx.Environment != "Sandbox",
		tx.BundleID != v.BundleID, tx.ProductID != productID, tx.RevocationDate != 0:
		return Grant{}, ErrInvalidProof
	case v.API != nil && v.API.revoked(ctx, v, tx, now):
		return Grant{}, ErrInvalidProof
	case tx.ExpiresDate == 0:
		return Grant{ProductID: productID}, nil
	}
	expires := time.UnixMilli(tx.ExpiresDate)
	if !now.Before(expires) {
		return Grant{}, ErrInvalidProof // a period that already ended
	}
	return Grant{ProductID: productID, Expires: expires}, nil
}

// verifyJWS returns the payload only once the x5c chain reaches the root and
// the leaf's signature holds.
func (v AppleVerifier) verifyJWS(data string) (appleTransaction, error) {
	parts := strings.Split(data, ".")
	if len(parts) != 3 {
		return appleTransaction{}, ErrInvalidProof
	}
	var header struct {
		Alg string   `json:"alg"`
		X5C []string `json:"x5c"`
	}
	var tx appleTransaction
	if decodeSegment(parts[0], &header) != nil || header.Alg != "ES256" || len(header.X5C) < 2 ||
		decodeSegment(parts[1], &tx) != nil {
		return appleTransaction{}, ErrInvalidProof
	}
	certs := make([]*x509.Certificate, len(header.X5C))
	for i, encoded := range header.X5C {
		der, err := base64.StdEncoding.DecodeString(encoded)
		if err != nil {
			return appleTransaction{}, ErrInvalidProof
		}
		if certs[i], err = x509.ParseCertificate(der); err != nil {
			return appleTransaction{}, ErrInvalidProof
		}
	}
	leaf := certs[0]
	intermediates := x509.NewCertPool()
	for _, c := range certs[1:] {
		intermediates.AddCert(c)
	}
	// Checked at signing time, like Apple's own library does offline: a
	// lifetime purchase from years ago is still valid after its leaf expired.
	// The payload is read before it is trusted only for this date.
	_, err := leaf.Verify(x509.VerifyOptions{
		Roots:         v.Roots,
		Intermediates: intermediates,
		CurrentTime:   time.UnixMilli(tx.SignedDate),
		KeyUsages:     []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	})
	if err != nil || !hasExtension(leaf, oidAppleReceiptLeaf) || !hasExtension(certs[1], oidAppleIntermediate) {
		return appleTransaction{}, ErrInvalidProof
	}
	key, ok := leaf.PublicKey.(*ecdsa.PublicKey)
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if !ok || err != nil || len(sig) != 64 {
		return appleTransaction{}, ErrInvalidProof
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r, s := new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(key, digest[:], r, s) {
		return appleTransaction{}, ErrInvalidProof
	}
	return tx, nil
}

func decodeSegment(segment string, dst any) error {
	raw, err := base64.RawURLEncoding.DecodeString(segment)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(raw, dst); err != nil {
		return fmt.Errorf("jws segment: %w", err)
	}
	return nil
}

func hasExtension(c *x509.Certificate, oid asn1.ObjectIdentifier) bool {
	for _, e := range c.Extensions {
		if e.Id.Equal(oid) {
			return true
		}
	}
	return false
}

// revoked reports whether Apple says the transaction was refunded or revoked.
// Only Apple's signed answer takes a purchase away: an outage, an unknown id
// or a bad response keeps the offline verdict, as Google's verifier does.
func (a *AppleAPI) revoked(ctx context.Context, v AppleVerifier, tx appleTransaction, now time.Time) bool {
	if tx.TransactionID == "" {
		return false
	}
	a.mu.Lock()
	hit, ok := a.cache[tx.TransactionID]
	a.mu.Unlock()
	if ok && now.Sub(hit.at) < cacheTTL {
		return hit.revoked
	}
	info, err := a.lookup(ctx, v, tx, now)
	if err != nil {
		slog.Warn("apple transaction lookup failed; using the offline verdict", "err", err)
		return false
	}
	revoked := info.RevocationDate != 0
	a.mu.Lock()
	if a.cache == nil || len(a.cache) >= cacheMax {
		a.cache = map[string]appleStatus{} // ponytail: dropped whole at the cap, as in google.go
	}
	a.cache[tx.TransactionID] = appleStatus{revoked: revoked, at: now}
	a.mu.Unlock()
	return revoked
}

func (a *AppleAPI) lookup(ctx context.Context, v AppleVerifier, tx appleTransaction, now time.Time) (appleTransaction, error) {
	base := a.BaseURL
	if base == "" {
		base = "https://api.storekit.itunes.apple.com"
		if tx.Environment == "Sandbox" {
			base = "https://api.storekit-sandbox.itunes.apple.com"
		}
	}
	token, err := a.token(v.BundleID, now)
	if err != nil {
		return appleTransaction{}, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base+"/inApps/v1/transactions/"+url.PathEscape(tx.TransactionID), nil)
	if err != nil {
		return appleTransaction{}, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	res, err := a.Client.Do(req)
	if err != nil {
		return appleTransaction{}, err
	}
	defer func() { _ = res.Body.Close() }()
	body, err := io.ReadAll(io.LimitReader(res.Body, maxGoogleResponse))
	if err != nil || res.StatusCode != http.StatusOK {
		return appleTransaction{}, fmt.Errorf("status %d: %v", res.StatusCode, err)
	}
	var out struct {
		SignedTransactionInfo string `json:"signedTransactionInfo"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return appleTransaction{}, err
	}
	info, err := v.verifyJWS(out.SignedTransactionInfo)
	if err != nil || info.TransactionID != tx.TransactionID {
		return appleTransaction{}, errors.New("unverifiable signedTransactionInfo")
	}
	return info, nil
}

// token is the App Store Server API's ES256 bearer JWT.
func (a *AppleAPI) token(bundleID string, now time.Time) (string, error) {
	enc := base64.RawURLEncoding
	header, _ := json.Marshal(map[string]string{"alg": "ES256", "kid": a.KeyID, "typ": "JWT"})
	claims, _ := json.Marshal(map[string]any{
		"iss": a.IssuerID, "iat": now.Unix(), "exp": now.Add(20 * time.Minute).Unix(),
		"aud": "appstoreconnect-v1", "bid": bundleID,
	})
	unsigned := enc.EncodeToString(header) + "." + enc.EncodeToString(claims)
	digest := sha256.Sum256([]byte(unsigned))
	r, s, err := ecdsa.Sign(rand.Reader, a.Key, digest[:])
	if err != nil {
		return "", err
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return unsigned + "." + enc.EncodeToString(sig), nil
}
