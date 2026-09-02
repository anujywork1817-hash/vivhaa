package unlock

import "time"

// Payment tracks the one-time ₹1 unlock charge — deliberately a separate,
// minimal table/model from internal/payments.Payment (which is tied to a
// plan_id/subscription_id), since this flow has neither.
type Payment struct {
	ID                string
	UserID            string
	AmountINR         int64
	Currency          string
	RazorpayOrderID   string
	RazorpayPaymentID *string
	RazorpaySignature *string
	Status            string
	CreatedAt         time.Time
	PaidAt            *time.Time
}
