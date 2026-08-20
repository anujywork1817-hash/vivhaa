package subscriptions

type PlanResponse struct {
	Code         string          `json:"code"`
	Name         string          `json:"name"`
	PriceINR     int64           `json:"price_inr"`
	DurationDays int             `json:"duration_days"`
	Features     map[string]bool `json:"features"`
	TierRank     int             `json:"tier_rank"`
}

type SubscriptionResponse struct {
	Status   string  `json:"status"`
	PlanCode string  `json:"plan_code"`
	StartsAt *string `json:"starts_at"`
	EndsAt   *string `json:"ends_at"`
}
