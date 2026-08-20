package payments

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"

	"matrimony-backend/internal/coupons"
	"matrimony-backend/internal/subscriptions"
)

var (
	ErrPlanNotFound       = errors.New("plan not found")
	ErrCannotCheckoutFree = errors.New("the free plan does not require checkout")
	ErrNotAnUpgrade       = errors.New("you can only switch to a plan higher than your current one")
	ErrInvalidSignature   = errors.New("payment signature verification failed")
	ErrAlreadyProcessed   = errors.New("this payment has already been processed")
	ErrPaymentNotCaptured = errors.New("payment was not captured for the expected amount")
)

type Service struct {
	repo          *Repository
	subsRepo      *subscriptions.Repository
	couponsSvc    *coupons.Service
	gateway       Gateway
	webhookSecret string
}

func NewService(repo *Repository, subsRepo *subscriptions.Repository, couponsSvc *coupons.Service, gateway Gateway, webhookSecret string) *Service {
	return &Service{repo: repo, subsRepo: subsRepo, couponsSvc: couponsSvc, gateway: gateway, webhookSecret: webhookSecret}
}

func (s *Service) Checkout(ctx context.Context, userID string, req CheckoutRequest) (CheckoutResponse, error) {
	plan, err := s.subsRepo.GetPlanByCode(ctx, req.PlanCode)
	if errors.Is(err, subscriptions.ErrNotFound) {
		return CheckoutResponse{}, ErrPlanNotFound
	}
	if err != nil {
		return CheckoutResponse{}, err
	}
	if plan.Code == "free" {
		return CheckoutResponse{}, ErrCannotCheckoutFree
	}

	// Enforced server-side, not just in the app's plan picker — this is a
	// business rule ("only ever upgrade, never sideways or down"), and the
	// UI filtering the list is a convenience, not the actual gate. Without
	// this, a replayed or hand-crafted checkout request could still buy a
	// same-or-lower tier than the caller already has.
	currentTierRank, err := s.currentTierRank(ctx, userID)
	if err != nil {
		return CheckoutResponse{}, err
	}
	if plan.TierRank <= currentTierRank {
		return CheckoutResponse{}, ErrNotAnUpgrade
	}

	amount := plan.PriceINR
	var discount int64
	var couponID *string
	if req.CouponCode != nil && *req.CouponCode != "" {
		coupon, disc, err := s.couponsSvc.Apply(ctx, *req.CouponCode, amount)
		if err != nil {
			return CheckoutResponse{}, err
		}
		discount = disc
		couponID = &coupon.ID
	}
	finalAmount := amount - discount

	pendingSub, err := s.subsRepo.CreatePending(ctx, userID, plan.ID)
	if err != nil {
		return CheckoutResponse{}, err
	}

	order, err := s.gateway.CreateOrder(ctx, finalAmount*100, "INR", pendingSub.ID)
	if err != nil {
		return CheckoutResponse{}, err
	}

	payment, err := s.repo.Create(ctx, userID, plan.ID, pendingSub.ID, order.ID, finalAmount, discount, couponID)
	if err != nil {
		return CheckoutResponse{}, err
	}

	return CheckoutResponse{
		PaymentID:   payment.ID,
		OrderID:     order.ID,
		AmountPaise: finalAmount * 100,
		Currency:    "INR",
		KeyID:       s.gateway.KeyID(),
		DiscountINR: discount,
	}, nil
}

// currentTierRank returns the tier_rank of the caller's current active,
// non-expired plan — 0 (free) if they have none. Mirrors the same
// active-subscription lookup subscriptions.Service.GetMine does; kept
// local since payments has no other reason to depend on that service.
func (s *Service) currentTierRank(ctx context.Context, userID string) (int, error) {
	sub, err := s.subsRepo.GetActiveByUserID(ctx, userID)
	if errors.Is(err, subscriptions.ErrNotFound) {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	plan, err := s.subsRepo.GetPlanByID(ctx, sub.PlanID)
	if err != nil {
		return 0, err
	}
	return plan.TierRank, nil
}

// Verify checks the payment signature returned by the checkout widget,
// independently confirms with the gateway that the full amount was
// actually captured (not just that the signature is genuine — see
// FetchedPayment's doc), and if both hold, activates the pending
// subscription tied to this order.
func (s *Service) Verify(ctx context.Context, userID string, req VerifyRequest) (VerifyResponse, error) {
	payment, err := s.repo.GetByOrderID(ctx, req.OrderID)
	if errors.Is(err, ErrNotFound) {
		return VerifyResponse{}, ErrNotFound
	}
	if err != nil {
		return VerifyResponse{}, err
	}
	if payment.UserID != userID {
		return VerifyResponse{}, ErrNotFound
	}
	// Fast, non-locking pre-check: not the actual concurrency guard (that's
	// the FOR UPDATE re-check inside finalizeCapturedPayment) — just avoids
	// wasting a signature check + FetchPayment network round-trip on a
	// payment that's obviously already settled.
	if payment.Status != "created" {
		return VerifyResponse{}, ErrAlreadyProcessed
	}

	if !s.gateway.VerifySignature(req.OrderID, req.PaymentID, req.Signature) {
		_ = s.repo.MarkFailed(ctx, payment.ID)
		return VerifyResponse{}, ErrInvalidSignature
	}

	fetched, err := s.gateway.FetchPayment(ctx, req.PaymentID)
	if err != nil {
		return VerifyResponse{}, err
	}
	if fetched.OrderID != req.OrderID || fetched.Status != "captured" {
		_ = s.repo.MarkFailed(ctx, payment.ID)
		return VerifyResponse{}, ErrPaymentNotCaptured
	}

	return s.finalizeCapturedPayment(ctx, req.OrderID, req.PaymentID, req.Signature, fetched.AmountPaise, fetched.Currency)
}

// finalizeCapturedPayment is the single place both the client-driven
// Verify() and the server-driven webhook (ActivateFromWebhook) converge,
// once each has independently established — by its own means — that
// Razorpay actually captured the expected amount. Runs the authoritative
// status check, MarkPaid, and subscription Activate in one transaction
// with the payment row locked (FOR UPDATE) for its duration, so two
// concurrent calls for the same order can't both pass the status check
// and double-activate (BUG-H04), and returning ErrAlreadyProcessed here
// rather than erroring is what makes both callers safe to invoke more
// than once for the same payment (BUG-H05's webhook redelivery included).
func (s *Service) finalizeCapturedPayment(ctx context.Context, orderID, gatewayPaymentID, signature string, capturedAmountPaise int64, capturedCurrency string) (VerifyResponse, error) {
	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return VerifyResponse{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	payment, err := s.repo.GetByOrderIDForUpdate(ctx, tx, orderID)
	if errors.Is(err, ErrNotFound) {
		return VerifyResponse{}, ErrNotFound
	}
	if err != nil {
		return VerifyResponse{}, err
	}
	if payment.Status != "created" {
		return VerifyResponse{}, ErrAlreadyProcessed
	}
	if payment.SubscriptionID == nil {
		return VerifyResponse{}, errors.New("payment has no associated subscription")
	}
	// Re-checked here, under the lock, against what was actually stored at
	// Checkout() time — not just trusting the caller already checked this
	// before opening the transaction.
	if payment.AmountINR*100 != capturedAmountPaise || payment.Currency != capturedCurrency {
		return VerifyResponse{}, ErrPaymentNotCaptured
	}

	plan, err := s.subsRepo.GetPlanByID(ctx, payment.PlanID)
	if err != nil {
		return VerifyResponse{}, err
	}

	if _, err := s.repo.MarkPaid(ctx, tx, payment.ID, gatewayPaymentID, signature); err != nil {
		return VerifyResponse{}, err
	}
	activated, err := s.subsRepo.Activate(ctx, tx, *payment.SubscriptionID, plan.DurationDays)
	if err != nil {
		return VerifyResponse{}, err
	}

	if err := tx.Commit(ctx); err != nil {
		return VerifyResponse{}, err
	}

	// Best-effort, outside the transaction — coupon usage-limit enforcement
	// under concurrency is BUG-M11's concern, not this one; unchanged from
	// before this fix.
	if payment.CouponID != nil {
		_ = s.couponsSvc.MarkUsed(ctx, *payment.CouponID)
	}

	var endsAt string
	if activated.EndsAt != nil {
		endsAt = activated.EndsAt.Format(time.RFC3339)
	}
	return VerifyResponse{Status: "active", SubscriptionPlan: plan.Code, SubscriptionEnds: endsAt}, nil
}

// ActivateFromWebhook is the server-driven counterpart to Verify() — see
// Handler.Webhook. The webhook payload's own signature (verified by the
// caller via VerifyWebhookSignature before this is called) is Razorpay
// itself pushing trusted data, so unlike Verify() there's no separate
// FetchPayment call to make: the payload already carries what FetchPayment
// would have returned.
func (s *Service) ActivateFromWebhook(ctx context.Context, orderID, paymentID string, amountPaise int64, currency, status string) error {
	if status != "captured" {
		// authorized-but-not-yet-captured, failed, refunded, etc. — nothing
		// to activate; a later payment.captured delivery (if one comes)
		// will do it.
		return nil
	}
	_, err := s.finalizeCapturedPayment(ctx, orderID, paymentID, "", amountPaise, currency)
	if errors.Is(err, ErrAlreadyProcessed) {
		// Not a failure — Verify() (or an earlier webhook delivery) may
		// have already finalized this order; that's exactly the
		// idempotency this endpoint needs, not an error to surface.
		return nil
	}
	return err
}

// VerifyWebhookSignature checks Razorpay's X-Razorpay-Signature header:
// hex(HMAC-SHA256(raw_request_body, RAZORPAY_WEBHOOK_SECRET)). Must run
// against the raw bytes before any JSON parsing — Razorpay signs exactly
// what it sent over the wire, not a round-tripped re-serialization of it.
func (s *Service) VerifyWebhookSignature(body []byte, signature string) bool {
	if s.webhookSecret == "" {
		// Unconfigured — refuse rather than accept an unverifiable payload.
		return false
	}
	mac := hmac.New(sha256.New, []byte(s.webhookSecret))
	mac.Write(body)
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(expected), []byte(signature))
}

// MockCompletePayment stands in for what Razorpay's checkout widget
// normally does (tell Razorpay's servers a payment happened) — only
// reachable when the mock gateway is active (see routes.go), never against
// the real one. Lets local/manual testing exercise the full
// checkout -> verify -> activate flow without a real Razorpay account: the
// returned payment_id/signature are exactly what a real checkout
// completion would hand the client, ready to submit to Verify().
func (s *Service) MockCompletePayment(ctx context.Context, orderID string) (paymentID, signature string, err error) {
	mock, ok := s.gateway.(*MockGateway)
	if !ok {
		return "", "", errors.New("mock payment completion is only available when the mock gateway is active")
	}
	payment, err := s.repo.GetByOrderID(ctx, orderID)
	if err != nil {
		return "", "", err
	}
	paymentID = "pay_mock_" + payment.ID
	mock.RecordPayment(paymentID, orderID, payment.AmountINR*100, payment.Currency, "captured")
	signature = computeHMAC(orderID, paymentID, mock.KeySecret())
	return paymentID, signature, nil
}

func (s *Service) ListHistory(ctx context.Context, userID string) ([]PaymentResponse, error) {
	rows, err := s.repo.ListByUserWithPlan(ctx, userID, 50)
	if err != nil {
		return nil, err
	}
	out := make([]PaymentResponse, 0, len(rows))
	for _, p := range rows {
		var paidAt *string
		if p.PaidAt != nil {
			v := p.PaidAt.Format(time.RFC3339)
			paidAt = &v
		}
		out = append(out, PaymentResponse{
			ID: p.ID, PlanID: p.PlanID, PlanCode: p.PlanCode, PlanName: p.PlanName,
			AmountINR: p.AmountINR, DiscountINR: p.DiscountINR,
			Status: p.Status, CreatedAt: p.CreatedAt.Format(time.RFC3339), PaidAt: paidAt,
		})
	}
	return out, nil
}
