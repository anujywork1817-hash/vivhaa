package jwt

import (
	"testing"
	"time"

	gojwt "github.com/golang-jwt/jwt/v5"
)

const testSecret = "test-secret-do-not-use-in-production"

func TestGenerateAndVerify_RoundTrip(t *testing.T) {
	issuer := NewIssuer(testSecret, time.Hour)

	token, expiresAt, err := issuer.Generate("user-123", "admin")
	if err != nil {
		t.Fatalf("Generate returned error: %v", err)
	}
	if token == "" {
		t.Fatal("Generate returned an empty token")
	}
	if !expiresAt.After(time.Now()) {
		t.Fatalf("expiresAt %v is not in the future", expiresAt)
	}

	claims, err := issuer.Verify(token)
	if err != nil {
		t.Fatalf("Verify returned error: %v", err)
	}
	if claims.UserID != "user-123" {
		t.Errorf("UserID = %q, want %q", claims.UserID, "user-123")
	}
	if claims.Role != "admin" {
		t.Errorf("Role = %q, want %q", claims.Role, "admin")
	}
}

// A token signed with a different secret must not validate — otherwise
// anyone could mint their own tokens and impersonate any user.
func TestVerify_RejectsTokenSignedWithAnotherSecret(t *testing.T) {
	attacker := NewIssuer("attacker-secret", time.Hour)
	victim := NewIssuer(testSecret, time.Hour)

	forged, _, err := attacker.Generate("user-123", "admin")
	if err != nil {
		t.Fatalf("Generate returned error: %v", err)
	}

	if _, err := victim.Verify(forged); err == nil {
		t.Fatal("token signed with a foreign secret was accepted")
	}
}

func TestVerify_RejectsExpiredToken(t *testing.T) {
	// Negative TTL puts `exp` in the past the moment it's issued.
	issuer := NewIssuer(testSecret, -time.Minute)

	token, _, err := issuer.Generate("user-123", "user")
	if err != nil {
		t.Fatalf("Generate returned error: %v", err)
	}

	if _, err := issuer.Verify(token); err == nil {
		t.Fatal("expired token was accepted")
	}
}

// The classic JWT "alg=none" downgrade: an unsigned token carrying
// admin claims must be refused rather than trusted.
func TestVerify_RejectsUnsignedToken(t *testing.T) {
	issuer := NewIssuer(testSecret, time.Hour)

	claims := Claims{
		UserID: "user-123",
		Role:   "admin",
		RegisteredClaims: gojwt.RegisteredClaims{
			ExpiresAt: gojwt.NewNumericDate(time.Now().Add(time.Hour)),
		},
	}
	unsigned, err := gojwt.NewWithClaims(gojwt.SigningMethodNone, claims).
		SignedString(gojwt.UnsafeAllowNoneSignatureType)
	if err != nil {
		t.Fatalf("building unsigned token: %v", err)
	}

	if _, err := issuer.Verify(unsigned); err == nil {
		t.Fatal("alg=none token was accepted")
	}
}

func TestVerify_RejectsMalformedInput(t *testing.T) {
	issuer := NewIssuer(testSecret, time.Hour)

	for _, token := range []string{"", "not-a-jwt", "a.b.c", "Bearer something"} {
		if _, err := issuer.Verify(token); err == nil {
			t.Errorf("malformed token %q was accepted", token)
		}
	}
}

// Tampering with the payload invalidates the signature, so an escalated
// role can't be smuggled through by editing a genuine token.
func TestVerify_RejectsTamperedPayload(t *testing.T) {
	issuer := NewIssuer(testSecret, time.Hour)

	token, _, err := issuer.Generate("user-123", "user")
	if err != nil {
		t.Fatalf("Generate returned error: %v", err)
	}

	// Flip a character in the payload segment.
	tampered := []byte(token)
	dot := 0
	for i, c := range tampered {
		if c == '.' {
			dot = i
			break
		}
	}
	if tampered[dot+1] == 'a' {
		tampered[dot+1] = 'b'
	} else {
		tampered[dot+1] = 'a'
	}

	if _, err := issuer.Verify(string(tampered)); err == nil {
		t.Fatal("tampered token was accepted")
	}
}
