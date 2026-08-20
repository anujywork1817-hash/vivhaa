package payments

type CheckoutRequest struct {
	PlanCode   string  `json:"plan_code" validate:"required"`
	CouponCode *string `json:"coupon_code"`
}

type CheckoutResponse struct {
	PaymentID   string `json:"payment_id"`
	OrderID     string `json:"razorpay_order_id"`
	AmountPaise int64  `json:"amount_paise"`
	Currency    string `json:"currency"`
	KeyID       string `json:"razorpay_key_id"`
	DiscountINR int64  `json:"discount_inr"`
}

type VerifyRequest struct {
	OrderID   string `json:"razorpay_order_id" validate:"required"`
	PaymentID string `json:"razorpay_payment_id" validate:"required"`
	Signature string `json:"razorpay_signature" validate:"required"`
}

type VerifyResponse struct {
	Status           string `json:"status"`
	SubscriptionPlan string `json:"subscription_plan"`
	SubscriptionEnds string `json:"subscription_ends_at"`
}

type PaymentResponse struct {
	ID          string  `json:"id"`
	PlanID      string  `json:"plan_id"`
	PlanCode    string  `json:"plan_code"`
	PlanName    string  `json:"plan_name"`
	AmountINR   int64   `json:"amount_inr"`
	DiscountINR int64   `json:"discount_inr"`
	Status      string  `json:"status"`
	CreatedAt   string  `json:"created_at"`
	PaidAt      *string `json:"paid_at"`
}
