package coupons

import (
	"context"
	"errors"
	"time"
)

var (
	ErrInactive  = errors.New("coupon is not active")
	ErrExpired   = errors.New("coupon has expired or is not yet valid")
	ErrExhausted = errors.New("coupon has reached its usage limit")
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// Apply validates code against the current time/usage limits and returns
// the coupon plus the discount (in INR) it grants on amountINR.
func (s *Service) Apply(ctx context.Context, code string, amountINR int64) (Coupon, int64, error) {
	c, err := s.repo.GetByCode(ctx, code)
	if err != nil {
		return Coupon{}, 0, err
	}

	if !c.IsActive {
		return Coupon{}, 0, ErrInactive
	}

	now := time.Now()
	if now.Before(c.ValidFrom) || (c.ValidUntil != nil && now.After(*c.ValidUntil)) {
		return Coupon{}, 0, ErrExpired
	}

	if c.MaxUses != nil && c.UsedCount >= *c.MaxUses {
		return Coupon{}, 0, ErrExhausted
	}

	var discount int64
	switch c.DiscountType {
	case "percent":
		discount = amountINR * c.DiscountValue / 100
	case "flat":
		discount = c.DiscountValue
	}
	// Only DiscountValue's upper bound was ever clamped (below) — a
	// negative value (bad seed data, a direct DB edit; there's no admin
	// API for coupons today) would otherwise flow straight through as a
	// negative discount, INCREASING the final charge instead of reducing
	// it.
	if discount < 0 {
		discount = 0
	}
	if discount > amountINR {
		discount = amountINR
	}

	return c, discount, nil
}

// Reserve atomically claims one use of the coupon — called at checkout
// time (not payment-verify time) so the max-uses limit is actually
// enforced at the point where two concurrent requests could otherwise
// both pass Apply()'s check. Returns ErrExhausted if the limit was hit
// (by this call or a concurrent one) since Apply() ran.
func (s *Service) Reserve(ctx context.Context, couponID string) error {
	return s.repo.IncrementUsage(ctx, couponID)
}

// Release undoes a Reserve for a checkout that didn't end up completing
// (gateway order creation failed, the payment row failed to write, ...) —
// the same compensation pattern payments.Service uses for the pending
// subscription row it creates alongside this reservation.
func (s *Service) Release(ctx context.Context, couponID string) error {
	return s.repo.DecrementUsage(ctx, couponID)
}
