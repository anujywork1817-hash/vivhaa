package payments

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"

	"matrimony-backend/configs"
)

// signature computes what Razorpay's checkout widget would send back for a
// given order/payment pair, so tests can produce genuinely valid inputs
// rather than asserting against hard-coded strings.
func signature(orderID, paymentID, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(orderID + "|" + paymentID))
	return hex.EncodeToString(mac.Sum(nil))
}

func TestVerifySignature_AcceptsValidSignature(t *testing.T) {
	g := NewMockGateway("", "")
	orderID, paymentID := "order_abc123", "pay_xyz789"

	valid := signature(orderID, paymentID, g.KeySecret())

	if !g.VerifySignature(orderID, paymentID, valid) {
		t.Fatal("a correctly computed signature was rejected")
	}
}

// Every one of these is a payment that must not be able to activate a
// subscription: forged signatures, and valid signatures replayed against a
// different order or payment than the one they were issued for.
func TestVerifySignature_RejectsInvalid(t *testing.T) {
	g := NewMockGateway("", "")
	const orderID, paymentID = "order_abc123", "pay_xyz789"
	valid := signature(orderID, paymentID, g.KeySecret())

	tests := []struct {
		name                          string
		orderID, paymentID, signature string
	}{
		{name: "empty signature", orderID: orderID, paymentID: paymentID, signature: ""},
		{name: "garbage signature", orderID: orderID, paymentID: paymentID, signature: "deadbeef"},
		{
			name:      "signature computed with a different secret",
			orderID:   orderID,
			paymentID: paymentID,
			signature: signature(orderID, paymentID, "some-other-secret"),
		},
		{
			name:      "valid signature replayed for another order",
			orderID:   "order_someone_elses",
			paymentID: paymentID,
			signature: valid,
		},
		{
			name:      "valid signature replayed for another payment",
			orderID:   orderID,
			paymentID: "pay_different",
			signature: valid,
		},
		{
			name:      "order and payment swapped",
			orderID:   paymentID,
			paymentID: orderID,
			signature: valid,
		},
		{
			name:      "signature uppercased",
			orderID:   orderID,
			paymentID: paymentID,
			signature: strings.ToUpper(valid),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if g.VerifySignature(tt.orderID, tt.paymentID, tt.signature) {
				t.Fatal("an invalid signature was accepted")
			}
		})
	}
}

// Pins the exact bytes that get signed. This is Razorpay's documented
// scheme (`order_id + "|" + payment_id`, HMAC-SHA256, hex) and must not be
// "improved" — any change here stops real Razorpay callbacks from
// verifying, silently failing every live payment.
//
// A known, accepted property of that scheme: because the parts are simply
// concatenated, an id containing "|" would make the split ambiguous
// (order "a|b" + payment "c" hashes identically to order "a" + payment
// "b|c"). It isn't exploitable because Razorpay ids are `order_…`/`pay_…`
// alphanumerics that never contain the separator, and the ids are issued
// by Razorpay rather than chosen by the payer. Documented here so the
// behaviour is a deliberate trade-off rather than a surprise.
func TestVerifySignature_UsesRazorpayDocumentedScheme(t *testing.T) {
	const secret = "fixed-secret-for-vector"
	g := NewMockGateway("rzp_test_x", secret)

	// Independently computed expectation, not taken from the implementation.
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte("order_abc123|pay_xyz789"))
	want := hex.EncodeToString(mac.Sum(nil))

	if !g.VerifySignature("order_abc123", "pay_xyz789", want) {
		t.Fatal("signature built to Razorpay's documented scheme was rejected")
	}

	// The separator itself matters: signing without it must not verify.
	macNoSep := hmac.New(sha256.New, []byte(secret))
	macNoSep.Write([]byte("order_abc123pay_xyz789"))
	if g.VerifySignature("order_abc123", "pay_xyz789", hex.EncodeToString(macNoSep.Sum(nil))) {
		t.Fatal("signature computed without the '|' separator was accepted")
	}
}

func TestMockGateway_CreateOrderProducesUniqueIDs(t *testing.T) {
	g := NewMockGateway("", "")
	ctx := context.Background()

	seen := make(map[string]bool)
	for i := 0; i < 50; i++ {
		order, err := g.CreateOrder(ctx, 99900, "INR", "receipt")
		if err != nil {
			t.Fatalf("CreateOrder returned error: %v", err)
		}
		if seen[order.ID] {
			t.Fatalf("duplicate order id generated: %s", order.ID)
		}
		seen[order.ID] = true

		if order.AmountPaise != 99900 {
			t.Errorf("AmountPaise = %d, want 99900", order.AmountPaise)
		}
		if order.Currency != "INR" {
			t.Errorf("Currency = %q, want INR", order.Currency)
		}
	}
}

// Real credentials must select the real gateway; anything less falls back
// to the mock in non-strict (dev) mode. A half-configured environment (key
// but no secret) must not be mistaken for production.
func TestNewGateway_SelectsImplementation(t *testing.T) {
	tests := []struct {
		name     string
		cfg      configs.RazorpayConfig
		wantReal bool
	}{
		{name: "no credentials", cfg: configs.RazorpayConfig{}},
		{name: "key only", cfg: configs.RazorpayConfig{KeyID: "rzp_test_x"}},
		{name: "secret only", cfg: configs.RazorpayConfig{KeySecret: "s3cret"}},
		{
			name:     "both provided",
			cfg:      configs.RazorpayConfig{KeyID: "rzp_test_x", KeySecret: "s3cret"},
			wantReal: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g, err := NewGateway(tt.cfg, false)
			if err != nil {
				t.Fatalf("NewGateway(strict=false) returned unexpected error: %v", err)
			}
			_, isReal := g.(*RazorpayGateway)
			if isReal != tt.wantReal {
				t.Fatalf("NewGateway returned real=%v, want real=%v", isReal, tt.wantReal)
			}
		})
	}
}

// BUG-C04: outside dev mode (strict=true), missing credentials must be a
// fatal startup error, never a silent fallback to the mock gateway — the
// mock's signature check accepts a publicly known constant secret, so
// booting on it in prod would let anyone activate a paid plan for free.
func TestNewGateway_StrictModeRefusesMockFallback(t *testing.T) {
	_, err := NewGateway(configs.RazorpayConfig{}, true)
	if err == nil {
		t.Fatal("NewGateway(strict=true) with no credentials returned no error — it must refuse to fall back to the mock gateway")
	}

	g, err := NewGateway(configs.RazorpayConfig{KeyID: "rzp_test_x", KeySecret: "s3cret"}, true)
	if err != nil {
		t.Fatalf("NewGateway(strict=true) with real credentials returned an error: %v", err)
	}
	if _, isReal := g.(*RazorpayGateway); !isReal {
		t.Fatal("NewGateway(strict=true) with real credentials did not return the real gateway")
	}
}

// The mock gateway can't observe a real checkout completing on its own —
// FetchPayment must refuse an unrecorded payment_id rather than fabricate
// a plausible-looking "captured" response, which would silently defeat
// BUG-H06's whole point even in the mock.
func TestMockGateway_FetchPaymentRequiresRecordedPayment(t *testing.T) {
	g := NewMockGateway("", "")
	ctx := context.Background()

	if _, err := g.FetchPayment(ctx, "pay_never_recorded"); err == nil {
		t.Fatal("FetchPayment for an unrecorded payment_id returned no error")
	}

	g.RecordPayment("pay_abc", "order_abc", 99900, "INR", "captured")
	fetched, err := g.FetchPayment(ctx, "pay_abc")
	if err != nil {
		t.Fatalf("FetchPayment for a recorded payment returned an error: %v", err)
	}
	if fetched.OrderID != "order_abc" || fetched.AmountPaise != 99900 || fetched.Currency != "INR" || fetched.Status != "captured" {
		t.Fatalf("FetchPayment returned %+v, want the exact values passed to RecordPayment", fetched)
	}
}
