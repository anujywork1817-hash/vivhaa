package coupons

import "time"

type Coupon struct {
	ID            string
	Code          string
	Description   *string
	DiscountType  string // percent, flat
	DiscountValue int64
	MaxUses       *int
	UsedCount     int
	ValidFrom     time.Time
	ValidUntil    *time.Time
	IsActive      bool
}
