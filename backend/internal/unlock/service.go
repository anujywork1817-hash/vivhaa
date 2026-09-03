// Package unlock implements the one-time ₹1 "pay to continue" gate that
// sits in front of every real (non-demo) feature — separate from and
// unrelated to the plan-based subscription/premium tier system in
// internal/subscriptions/internal/payments, which keeps working exactly
// as before once a user is unlocked. Reuses the same payments.Gateway
// abstraction (Razorpay or the mock, whichever internal/payments wired up)
// rather than reimplementing gateway integration.
package unlock

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"log/slog"
	"time"

	"matrimony-backend/internal/payments"
	"matrimony-backend/internal/users"
)

const (
	// reconcileMinAge excludes orders too young to check — a user may
	// simply be mid-checkout right now, and reconciling those would race
	// their own in-flight /verify call.
	reconcileMinAge = 15 * time.Minute
	// reconcileAbandonAfter is how long an order can sit at "created"
	// with no captured payment on Razorpay's side before Reconcile gives
	// up and marks it failed, rather than checking it forever.
	reconcileAbandonAfter = 24 * time.Hour
)

const (
	unlockAmountINR   int64 = 1
	unlockCurrency          = "INR"
)

// ErrNotFound is the same sentinel repository.go's scan() returns —
// declared there, reused here.
var (
	ErrInvalidSignature   = errors.New("payment signature verification failed")
	ErrAlreadyProcessed   = errors.New("this payment has already been processed")
	ErrPaymentNotCaptured = errors.New("payment was not captured for the expected amount")
)

type Service struct {
	repo      *Repository
	usersRepo *users.Repository
	gateway   payments.Gateway
}

func NewService(repo *Repository, usersRepo *users.Repository, gateway payments.Gateway) *Service {
	return &Service{repo: repo, usersRepo: usersRepo, gateway: gateway}
}

// Checkout returns {unlocked: true} without creating a new order if the
// caller already paid, reuses a still-pending order if one exists (so
// repeatedly opening the paywall screen doesn't spawn a fresh Razorpay
// order every time), and otherwise creates one for exactly ₹1 (100 paise).
func (s *Service) Checkout(ctx context.Context, userID string) (CheckoutResponse, error) {
	unlocked, err := s.usersRepo.IsUnlocked(ctx, userID)
	if err != nil {
		return CheckoutResponse{}, err
	}
	if unlocked {
		return CheckoutResponse{Unlocked: true}, nil
	}

	if pending, err := s.repo.GetLatestPendingByUserID(ctx, userID); err == nil {
		return CheckoutResponse{
			Unlocked:    false,
			PaymentID:   pending.ID,
			OrderID:     pending.RazorpayOrderID,
			AmountPaise: pending.AmountINR * 100,
			Currency:    pending.Currency,
			KeyID:       s.gateway.KeyID(),
		}, nil
	} else if !errors.Is(err, ErrNotFound) {
		return CheckoutResponse{}, err
	}

	// Razorpay caps `receipt` at 40 characters — "unlock:" (7) + a UUID (36)
	// is 43, which Razorpay's API silently rejects with a 400, surfacing to
	// the client as an opaque 500 with nothing to explain it. "u:" (2) + the
	// UUID fits comfortably under the limit.
	order, err := s.gateway.CreateOrder(ctx, unlockAmountINR*100, unlockCurrency, "u:"+userID)
	if err != nil {
		return CheckoutResponse{}, err
	}

	payment, err := s.repo.Create(ctx, userID, order.ID, unlockAmountINR, unlockCurrency)
	if err != nil {
		return CheckoutResponse{}, err
	}

	return CheckoutResponse{
		Unlocked:    false,
		PaymentID:   payment.ID,
		OrderID:     order.ID,
		AmountPaise: unlockAmountINR * 100,
		Currency:    unlockCurrency,
		KeyID:       s.gateway.KeyID(),
	}, nil
}

// Verify mirrors payments.Service.Verify/finalizeCapturedPayment exactly:
// checks the checkout widget's signature, independently confirms with the
// gateway that the full ₹1 was actually captured, then — under a locked
// transaction re-checking status, the same double-processing guard
// finalizeCapturedPayment uses — marks the payment paid and the user
// unlocked.
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
	if payment.Status != "created" {
		if payment.Status == "paid" {
			return VerifyResponse{Unlocked: true}, nil
		}
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
		if payment.Status == "paid" {
			return VerifyResponse{Unlocked: true}, nil
		}
		return VerifyResponse{}, ErrAlreadyProcessed
	}
	if payment.AmountINR*100 != capturedAmountPaise || payment.Currency != capturedCurrency {
		return VerifyResponse{}, ErrPaymentNotCaptured
	}

	if _, err := s.repo.MarkPaid(ctx, tx, payment.ID, gatewayPaymentID, signature); err != nil {
		return VerifyResponse{}, err
	}

	if err := tx.Commit(ctx); err != nil {
		return VerifyResponse{}, err
	}

	// MarkUnlocked runs outside the unlock_payments transaction (users is
	// a different table with its own row lock, and MarkUnlocked is
	// idempotent via COALESCE) — mirrors ActivateFromWebhook/Verify's
	// split in internal/payments, where the payment row's own status is
	// the source of truth for "did this already happen."
	if err := s.usersRepo.MarkUnlocked(ctx, payment.UserID); err != nil {
		slog.Error("unlock: payment marked paid but MarkUnlocked failed", "user_id", payment.UserID, "payment_id", payment.ID, "error", err)
		return VerifyResponse{}, err
	}

	return VerifyResponse{Unlocked: true}, nil
}

// MockCompletePayment stands in for Razorpay's checkout widget completing
// a payment — only reachable when the mock gateway is active (see
// routes.go), exactly mirroring payments.Service.MockCompletePayment.
func (s *Service) MockCompletePayment(ctx context.Context, orderID string) (paymentID, signature string, err error) {
	mock, ok := s.gateway.(*payments.MockGateway)
	if !ok {
		return "", "", errors.New("mock payment completion is only available when the mock gateway is active")
	}
	payment, err := s.repo.GetByOrderID(ctx, orderID)
	if err != nil {
		return "", "", err
	}
	paymentID = "pay_mock_unlock_" + payment.ID
	mock.RecordPayment(paymentID, orderID, payment.AmountINR*100, payment.Currency, "captured")
	signature = computeHMAC(orderID, paymentID, mock.KeySecret())
	return paymentID, signature, nil
}

// computeHMAC mirrors internal/payments' unexported helper of the same
// name (and MockGateway.VerifySignature's own use of it) — duplicated
// rather than exported from payments, since this is the one place outside
// that package that needs to compute a signature the mock gateway will
// accept, purely for MockCompletePayment's local/test flow.
func computeHMAC(orderID, paymentID, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(orderID + "|" + paymentID))
	return hex.EncodeToString(mac.Sum(nil))
}

// Reconcile sweeps every order stuck at "created" for long enough that
// it's not just a user mid-checkout, and cross-checks each one against
// Razorpay's own records — catching the case where a payment actually
// captured but our /verify callback never fired (closed tab, network
// drop, or a missed webhook), which would otherwise leave real money
// collected with no record of it here. Orders abandoned long enough with
// no captured payment on Razorpay's side either are marked failed so
// they stop showing up as "checkout started" forever.
func (s *Service) Reconcile(ctx context.Context) (ReconcileResponse, error) {
	stale, err := s.repo.ListStalePending(ctx, reconcileMinAge)
	if err != nil {
		return ReconcileResponse{}, err
	}

	var resp ReconcileResponse
	for _, payment := range stale {
		resp.Checked++

		attempts, err := s.gateway.FetchOrderPayments(ctx, payment.RazorpayOrderID)
		if err != nil {
			slog.Error("unlock: reconcile could not fetch order payments", "order_id", payment.RazorpayOrderID, "error", err)
			resp.StillPending++
			continue
		}

		var captured *payments.FetchedPayment
		for i := range attempts {
			if attempts[i].Status == "captured" {
				captured = &attempts[i]
				break
			}
		}

		if captured != nil {
			if _, err := s.finalizeCapturedPayment(ctx, payment.RazorpayOrderID, captured.ID, "admin-reconciled", captured.AmountPaise, captured.Currency); err != nil {
				slog.Error("unlock: reconcile found a captured payment but could not finalize it", "order_id", payment.RazorpayOrderID, "payment_id", captured.ID, "error", err)
				resp.StillPending++
				continue
			}
			resp.Reconciled++
			continue
		}

		if time.Since(payment.CreatedAt) > reconcileAbandonAfter {
			if err := s.repo.MarkFailed(ctx, payment.ID); err != nil {
				slog.Error("unlock: reconcile could not mark abandoned order failed", "order_id", payment.RazorpayOrderID, "error", err)
				resp.StillPending++
				continue
			}
			resp.MarkedFailed++
			continue
		}

		resp.StillPending++
	}

	return resp, nil
}

// Status reports whether userID has already completed the unlock payment.
func (s *Service) Status(ctx context.Context, userID string) (StatusResponse, error) {
	unlocked, err := s.usersRepo.IsUnlocked(ctx, userID)
	if err != nil {
		return StatusResponse{}, err
	}
	return StatusResponse{Unlocked: unlocked}, nil
}
