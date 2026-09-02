package unlock

type StatusResponse struct {
	Unlocked bool `json:"unlocked"`
}

type CheckoutResponse struct {
	Unlocked    bool   `json:"unlocked"`
	PaymentID   string `json:"payment_id,omitempty"`
	OrderID     string `json:"razorpay_order_id,omitempty"`
	AmountPaise int64  `json:"amount_paise,omitempty"`
	Currency    string `json:"currency,omitempty"`
	KeyID       string `json:"razorpay_key_id,omitempty"`
}

type VerifyRequest struct {
	OrderID   string `json:"razorpay_order_id" validate:"required"`
	PaymentID string `json:"razorpay_payment_id" validate:"required"`
	Signature string `json:"razorpay_signature" validate:"required"`
}

type VerifyResponse struct {
	Unlocked bool `json:"unlocked"`
}
