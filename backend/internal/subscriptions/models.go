package subscriptions

import "time"

type Plan struct {
	ID           string
	Code         string
	Name         string
	PriceINR     int64
	DurationDays int
	Features     map[string]bool
	IsActive     bool
	// Ordered tier rank — free=0, and each paid duration ranks above the
	// last. Used to decide whether one plan is an upgrade from another.
	TierRank int
}

type Subscription struct {
	ID        string
	UserID    string
	PlanID    string
	Status    string
	StartsAt  *time.Time
	EndsAt    *time.Time
	CreatedAt time.Time
}
