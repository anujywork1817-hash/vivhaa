package payments

import "context"

// Order is a payment gateway's created order, handed to the frontend to
// open its checkout widget.
type Order struct {
	ID          string
	AmountPaise int64
	Currency    string
}

// FetchedPayment is what the gateway independently reports about a
// payment_id, straight from its own servers — not anything the client
// submitted. A valid VerifySignature only proves the (orderID, paymentID)
// pairing is genuine; it does NOT prove the full amount was actually
// captured (Razorpay can validly sign an authorized-but-not-yet-captured
// or partially-captured payment too), so FetchPayment is the independent
// source of truth Verify() cross-checks against before activating anything.
type FetchedPayment struct {
	ID          string
	OrderID     string
	AmountPaise int64
	Currency    string
	Status      string // e.g. "captured", "authorized", "failed"
}

// Gateway abstracts the payment provider so a mock implementation can
// stand in when no real credentials are configured (see NewGateway).
type Gateway interface {
	// CreateOrder creates a payable order for amountPaise (INR, in paise).
	CreateOrder(ctx context.Context, amountPaise int64, currency, receipt string) (Order, error)
	// VerifySignature checks that (orderID, paymentID, signature) is a
	// genuine triple issued by the gateway for a completed payment.
	VerifySignature(orderID, paymentID, signature string) bool
	// FetchPayment independently confirms with the gateway what a payment
	// actually settled as, rather than trusting the signature alone.
	FetchPayment(ctx context.Context, paymentID string) (FetchedPayment, error)
	// FetchOrderPayments lists every payment attempt the gateway has on
	// file against orderID — the reconciliation path for an order stuck
	// at "created" in our own DB: the client may have completed checkout
	// but never called back to our /verify endpoint (closed tab, network
	// drop, missed webhook), in which case the gateway's own records are
	// the only place that capture is still visible.
	FetchOrderPayments(ctx context.Context, orderID string) ([]FetchedPayment, error)
	// KeyID is the public key the frontend checkout widget needs.
	KeyID() string
}
