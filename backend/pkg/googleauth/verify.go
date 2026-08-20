// Package googleauth verifies Google Sign-In ID tokens against Google's
// public JWKS, without pulling in the full google.golang.org/api client
// (which drags in gRPC, OpenTelemetry, and cloud-auth transitively for
// what is otherwise a plain RS256 JWT check).
package googleauth

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const jwksURL = "https://www.googleapis.com/oauth2/v3/certs"

var validIssuers = map[string]bool{
	"accounts.google.com":         true,
	"https://accounts.google.com": true,
}

// Claims is the subset of a verified Google ID token's payload this app
// needs to create or look up a local account.
type Claims struct {
	Subject       string // Google's stable per-user ID
	Email         string
	EmailVerified bool
	Name          string
}

// Verifier caches Google's signing keys (they rotate infrequently) so
// most verifications don't need a network round trip.
type Verifier struct {
	allowedAudiences map[string]bool
	client           *http.Client

	mu        sync.RWMutex
	keys      map[string]*rsa.PublicKey
	fetchedAt time.Time
}

func NewVerifier(allowedAudiences []string) *Verifier {
	audSet := make(map[string]bool, len(allowedAudiences))
	for _, a := range allowedAudiences {
		if a != "" {
			audSet[a] = true
		}
	}
	return &Verifier{
		allowedAudiences: audSet,
		client:           &http.Client{Timeout: 10 * time.Second},
		keys:             make(map[string]*rsa.PublicKey),
	}
}

// Verify checks idToken's signature, issuer, audience, and expiry, and
// returns its claims. Configured() must be true or every token is
// rejected — see Verifier.Configured.
func (v *Verifier) Verify(ctx context.Context, idToken string) (*Claims, error) {
	if len(v.allowedAudiences) == 0 {
		return nil, errors.New("google sign-in is not configured (no allowed audiences)")
	}

	token, err := jwt.Parse(idToken, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		kid, _ := t.Header["kid"].(string)
		return v.keyFor(ctx, kid)
	}, jwt.WithValidMethods([]string{"RS256"}))
	if err != nil || !token.Valid {
		return nil, fmt.Errorf("invalid google id token: %w", err)
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return nil, errors.New("invalid google id token claims")
	}

	iss, _ := claims["iss"].(string)
	if !validIssuers[iss] {
		return nil, fmt.Errorf("unexpected issuer: %s", iss)
	}

	aud, _ := claims["aud"].(string)
	if !v.allowedAudiences[aud] {
		return nil, fmt.Errorf("unrecognized audience: %s", aud)
	}

	email, _ := claims["email"].(string)
	emailVerified, _ := claims["email_verified"].(bool)
	name, _ := claims["name"].(string)
	sub, _ := claims["sub"].(string)

	if email == "" || sub == "" {
		return nil, errors.New("google id token missing required claims")
	}

	return &Claims{Subject: sub, Email: email, EmailVerified: emailVerified, Name: name}, nil
}

func (v *Verifier) Configured() bool {
	return len(v.allowedAudiences) > 0
}

func (v *Verifier) keyFor(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	v.mu.RLock()
	key, ok := v.keys[kid]
	stale := time.Since(v.fetchedAt) > time.Hour
	v.mu.RUnlock()
	if ok && !stale {
		return key, nil
	}

	if err := v.refreshKeys(ctx); err != nil {
		return nil, err
	}

	v.mu.RLock()
	defer v.mu.RUnlock()
	key, ok = v.keys[kid]
	if !ok {
		return nil, fmt.Errorf("no matching google signing key for kid %q", kid)
	}
	return key, nil
}

func (v *Verifier) refreshKeys(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, jwksURL, nil)
	if err != nil {
		return err
	}

	resp, err := v.client.Do(req)
	if err != nil {
		return fmt.Errorf("fetch google jwks: %w", err)
	}
	defer resp.Body.Close()

	var parsed struct {
		Keys []struct {
			Kid string `json:"kid"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return fmt.Errorf("decode google jwks: %w", err)
	}

	keys := make(map[string]*rsa.PublicKey, len(parsed.Keys))
	for _, k := range parsed.Keys {
		pub, err := rsaPublicKeyFromJWK(k.N, k.E)
		if err != nil {
			continue
		}
		keys[k.Kid] = pub
	}

	v.mu.Lock()
	v.keys = keys
	v.fetchedAt = time.Now()
	v.mu.Unlock()
	return nil
}

func rsaPublicKeyFromJWK(nB64, eB64 string) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(nB64)
	if err != nil {
		return nil, err
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(eB64)
	if err != nil {
		return nil, err
	}

	n := new(big.Int).SetBytes(nBytes)
	e := new(big.Int).SetBytes(eBytes)

	return &rsa.PublicKey{N: n, E: int(e.Int64())}, nil
}
