package payments

import "time"

type Payment struct {
	ID                string
	UserID            string
	PlanID            string
	SubscriptionID    *string
	CouponID          *string
	AmountINR         int64
	DiscountINR       int64
	Currency          string
	RazorpayOrderID   string
	RazorpayPaymentID *string
	RazorpaySignature *string
	Status            string
	CreatedAt         time.Time
	PaidAt            *time.Time
}
