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
	if discount > amountINR {
		discount = amountINR
	}

	return c, discount, nil
}

func (s *Service) MarkUsed(ctx context.Context, couponID string) error {
	return s.repo.IncrementUsage(ctx, couponID)
}
