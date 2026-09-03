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

// ReconcileResponse summarizes an admin-triggered sweep of orders stuck
// at "created" — see Service.Reconcile.
type ReconcileResponse struct {
	Checked      int `json:"checked"`
	Reconciled   int `json:"reconciled"` // found captured on Razorpay's side, now marked paid
	MarkedFailed int `json:"marked_failed"`
	StillPending int `json:"still_pending"` // checked, but Razorpay has no captured payment yet either
}
