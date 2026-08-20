package payments

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"matrimony-backend/internal/coupons"
	"matrimony-backend/internal/subscriptions"
	"matrimony-backend/pkg/testdb"
)

var testPhoneSeq int64

func uniquePhone(t *testing.T) string {
	t.Helper()
	n := atomic.AddInt64(&testPhoneSeq, 1)
	return fmt.Sprintf("+19256%06d%d", time.Now().Unix()%1000000, n%10)
}

// testEnv bundles a Service against the real test DB with a MockGateway,
// plus a throwaway active user to check out as.
type testEnv struct {
	svc     *Service
	gateway *MockGateway
	userID  string
}

func newTestEnv(t *testing.T) testEnv {
	t.Helper()
	pool := testdb.Connect(t)
	userID := testdb.NewUser(t, pool, uniquePhone(t))

	repo := NewRepository(pool)
	subsRepo := subscriptions.NewRepository(pool)
	couponsSvc := coupons.NewService(coupons.NewRepository(pool))
	gateway := NewMockGateway("", "")

	svc := NewService(repo, subsRepo, couponsSvc, gateway, "test-webhook-secret")
	return testEnv{svc: svc, gateway: gateway, userID: userID}
}

// checkoutPremium runs a real Checkout() against the "premium_monthly"
// plan seeded by migrations, returning the order/payment IDs a real
// checkout widget round-trip would hand back.
func (e testEnv) checkoutPremium(t *testing.T) CheckoutResponse {
	t.Helper()
	resp, err := e.svc.Checkout(context.Background(), e.userID, CheckoutRequest{PlanCode: "premium_monthly"})
	if err != nil {
		t.Fatalf("Checkout() error: %v", err)
	}
	return resp
}

// completeMockPayment mirrors what MockCompletePayment does — records the
// payment with the gateway and computes a valid signature for it, exactly
// as a real Razorpay checkout completion would hand the client.
func (e testEnv) completeMockPayment(t *testing.T, orderID string, amountPaise int64) (paymentID, signature string) {
	t.Helper()
	paymentID = "pay_mock_test_" + orderID
	e.gateway.RecordPayment(paymentID, orderID, amountPaise, "INR", "captured")
	signature = computeHMAC(orderID, paymentID, e.gateway.KeySecret())
	return paymentID, signature
}

func TestVerify_ActivatesSubscription(t *testing.T) {
	env := newTestEnv(t)
	ctx := context.Background()

	checkout := env.checkoutPremium(t)
	paymentID, signature := env.completeMockPayment(t, checkout.OrderID, checkout.AmountPaise)

	resp, err := env.svc.Verify(ctx, env.userID, VerifyRequest{
		OrderID: checkout.OrderID, PaymentID: paymentID, Signature: signature,
	})
	if err != nil {
		t.Fatalf("Verify() error: %v", err)
	}
	if resp.Status != "active" || resp.SubscriptionPlan != "premium_monthly" {
		t.Errorf("Verify() = %+v, want status=active plan=premium_monthly", resp)
	}

	sub, err := env.svc.subsRepo.GetActiveByUserID(ctx, env.userID)
	if err != nil {
		t.Fatalf("expected an active subscription after Verify(), got error: %v", err)
	}
	if sub.Status != "active" {
		t.Errorf("subscription status = %q, want active", sub.Status)
	}
}

func TestVerify_WrongSignature_MarksFailed(t *testing.T) {
	env := newTestEnv(t)
	ctx := context.Background()

	checkout := env.checkoutPremium(t)
	paymentID, _ := env.completeMockPayment(t, checkout.OrderID, checkout.AmountPaise)

	_, err := env.svc.Verify(ctx, env.userID, VerifyRequest{
		OrderID: checkout.OrderID, PaymentID: paymentID, Signature: "not-a-real-signature",
	})
	if !errors.Is(err, ErrInvalidSignature) {
		t.Errorf("Verify() with a bad signature = %v, want ErrInvalidSignature", err)
	}
}

func TestVerify_AmountMismatch_Rejected(t *testing.T) {
	env := newTestEnv(t)
	ctx := context.Background()

	checkout := env.checkoutPremium(t)
	// Gateway reports a captured amount that doesn't match what Checkout()
	// actually stored — simulates a tampered/replayed amount rather than
	// trusting whatever the client claims was paid.
	paymentID, signature := env.completeMockPayment(t, checkout.OrderID, 1)

	_, err := env.svc.Verify(ctx, env.userID, VerifyRequest{
		OrderID: checkout.OrderID, PaymentID: paymentID, Signature: signature,
	})
	if !errors.Is(err, ErrPaymentNotCaptured) {
		t.Errorf("Verify() with mismatched captured amount = %v, want ErrPaymentNotCaptured", err)
	}
}

// TestFinalizeCapturedPayment_ConcurrentCallsActivateExactlyOnce is the
// regression test for BUG-H04: two concurrent finalizers for the same
// order (e.g. the client's Verify() racing a webhook redelivery) must not
// both pass the status check and double-activate. Before the fix, both
// concurrent calls could observe payment.Status == "created" and both
// proceed; the FOR UPDATE row lock inside finalizeCapturedPayment (see
// service.go) is what makes exactly one of them win.
func TestFinalizeCapturedPayment_ConcurrentCallsActivateExactlyOnce(t *testing.T) {
	env := newTestEnv(t)

	checkout := env.checkoutPremium(t)
	paymentID, signature := env.completeMockPayment(t, checkout.OrderID, checkout.AmountPaise)

	const concurrency = 10
	var wg sync.WaitGroup
	var successes, alreadyProcessed, otherErrors int64

	for i := 0; i < concurrency; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := env.svc.Verify(context.Background(), env.userID, VerifyRequest{
				OrderID: checkout.OrderID, PaymentID: paymentID, Signature: signature,
			})
			switch {
			case err == nil:
				atomic.AddInt64(&successes, 1)
			case errors.Is(err, ErrAlreadyProcessed):
				atomic.AddInt64(&alreadyProcessed, 1)
			default:
				atomic.AddInt64(&otherErrors, 1)
				t.Logf("unexpected error from concurrent Verify(): %v", err)
			}
		}()
	}
	wg.Wait()

	if successes != 1 {
		t.Errorf("successful activations = %d, want exactly 1 (double-activation regression)", successes)
	}
	if otherErrors != 0 {
		t.Errorf("unexpected (non-ErrAlreadyProcessed) errors = %d, want 0", otherErrors)
	}
	if successes+alreadyProcessed != concurrency {
		t.Errorf("successes(%d) + alreadyProcessed(%d) = %d, want %d",
			successes, alreadyProcessed, successes+alreadyProcessed, concurrency)
	}

	// The payment itself must have settled into exactly one final state,
	// not been left ambiguous by two writers racing.
	payment, err := env.svc.repo.GetByOrderID(context.Background(), checkout.OrderID)
	if err != nil {
		t.Fatalf("GetByOrderID() error: %v", err)
	}
	if payment.Status != "paid" {
		t.Errorf("final payment status = %q, want paid", payment.Status)
	}
}

// TestActivateFromWebhook_IdempotentAfterVerify is the webhook-redelivery
// half of BUG-H04/BUG-H05: a webhook arriving after Verify() already
// finalized the same order must be a safe no-op, not an error surfaced to
// Razorpay (which would otherwise just retry it forever).
func TestActivateFromWebhook_IdempotentAfterVerify(t *testing.T) {
	env := newTestEnv(t)
	ctx := context.Background()

	checkout := env.checkoutPremium(t)
	paymentID, signature := env.completeMockPayment(t, checkout.OrderID, checkout.AmountPaise)

	if _, err := env.svc.Verify(ctx, env.userID, VerifyRequest{
		OrderID: checkout.OrderID, PaymentID: paymentID, Signature: signature,
	}); err != nil {
		t.Fatalf("Verify() error: %v", err)
	}

	// A webhook redelivery for the same, already-finalized order.
	err := env.svc.ActivateFromWebhook(ctx, checkout.OrderID, paymentID, checkout.AmountPaise, "INR", "captured")
	if err != nil {
		t.Errorf("ActivateFromWebhook() after Verify() already finalized = %v, want nil (idempotent no-op)", err)
	}
}
