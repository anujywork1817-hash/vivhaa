package payments

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"sync"
)

// MockGateway stands in for Razorpay when no real API credentials are
// configured (the dev default), so the full checkout -> pay -> verify ->
// subscription-activation flow can be exercised locally. It implements
// the exact same HMAC signature scheme Razorpay documents, so a test
// script holding the same secret can compute a valid payment_id +
// signature pair without ever calling Razorpay's servers.
type MockGateway struct {
	keyID     string
	keySecret string

	mu       sync.Mutex
	payments map[string]FetchedPayment
}

func NewMockGateway(keyID, keySecret string) *MockGateway {
	if keyID == "" {
		keyID = "rzp_test_mock_key_id"
	}
	if keySecret == "" {
		keySecret = "mock-secret-change-me"
	}
	return &MockGateway{keyID: keyID, keySecret: keySecret, payments: make(map[string]FetchedPayment)}
}

func (g *MockGateway) KeyID() string { return g.keyID }

func (g *MockGateway) CreateOrder(_ context.Context, amountPaise int64, currency, _ string) (Order, error) {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return Order{}, err
	}
	return Order{
		ID:          "order_mock_" + hex.EncodeToString(b),
		AmountPaise: amountPaise,
		Currency:    currency,
	}, nil
}

func (g *MockGateway) VerifySignature(orderID, paymentID, signature string) bool {
	return verifyHMAC(orderID, paymentID, signature, g.keySecret)
}

// RecordPayment registers what FetchPayment should report for paymentID.
// The mock has no way to observe a completed checkout on its own — a real
// checkout widget generates payment_id independently of anything this
// backend does — so local/test callers that fabricate a payment_id must
// tell the mock what it represents, the same way they'd need a real
// completed payment against Razorpay's test-mode API to exercise this for
// real. See Service.MockCompletePayment for the endpoint that drives this
// for manual/local testing.
func (g *MockGateway) RecordPayment(paymentID, orderID string, amountPaise int64, currency, status string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.payments[paymentID] = FetchedPayment{
		ID: paymentID, OrderID: orderID, AmountPaise: amountPaise, Currency: currency, Status: status,
	}
}

func (g *MockGateway) FetchPayment(_ context.Context, paymentID string) (FetchedPayment, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	p, ok := g.payments[paymentID]
	if !ok {
		return FetchedPayment{}, fmt.Errorf("mock gateway: no payment recorded for %q — call RecordPayment (or POST /payments/mock/complete) first", paymentID)
	}
	return p, nil
}

// FetchOrderPayments returns every recorded payment against orderID —
// the mock has no separate "order -> payments" index, so this is a
// linear scan of the same map FetchPayment reads, which is fine at
// mock/test scale.
func (g *MockGateway) FetchOrderPayments(_ context.Context, orderID string) ([]FetchedPayment, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	var out []FetchedPayment
	for _, p := range g.payments {
		if p.OrderID == orderID {
			out = append(out, p)
		}
	}
	return out, nil
}

// KeySecret exposes the mock secret so test tooling can compute a valid
// signature the same way Razorpay's real checkout widget would. Real
// gateways never expose this.
func (g *MockGateway) KeySecret() string { return g.keySecret }
