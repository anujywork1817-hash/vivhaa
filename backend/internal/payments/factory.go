package payments

import (
	"fmt"

	"matrimony-backend/configs"
)

// NewGateway returns the real Razorpay gateway when both key ID and secret
// are configured, otherwise a mock gateway suitable for local dev/testing.
//
// strict must be true outside dev mode (see configs.Load) — with it true,
// missing credentials are a fatal startup error instead of a silent
// fallback to MockGateway. The mock's VerifySignature accepts a publicly
// known constant secret ("mock-secret-change-me"), so a production
// deployment that silently booted on it would let anyone activate a paid
// plan for free; there's no safe way to "warn and continue" here.
func NewGateway(cfg configs.RazorpayConfig, strict bool) (Gateway, error) {
	if cfg.KeyID != "" && cfg.KeySecret != "" {
		return NewRazorpayGateway(cfg.KeyID, cfg.KeySecret), nil
	}
	if strict {
		return nil, fmt.Errorf("payments: RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET are not set — refusing to boot on the mock payment gateway outside dev mode")
	}
	return NewMockGateway(cfg.KeyID, cfg.KeySecret), nil
}
