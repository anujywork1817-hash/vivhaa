package admin

type UserResponse struct {
	ID            string  `json:"id"`
	Phone         *string `json:"phone"`
	Email         *string `json:"email"`
	PhoneVerified bool    `json:"phone_verified"`
	EmailVerified bool    `json:"email_verified"`
	Status        string  `json:"status"`
	Role          string  `json:"role"`
	LastLoginAt   *string `json:"last_login_at"`
	CreatedAt     string  `json:"created_at"`
}

type ListUsersMeta struct {
	Page  int `json:"page"`
	Limit int `json:"limit"`
	Total int `json:"total"`
}

// UserDetailResponse is GET /admin/users/:id's response — the account
// fields every list row already has, plus profile/subscription/
// verification context that only a detail view needs (so ListUsers,
// which returns one of these per row, doesn't pay for three extra joins
// per row it never uses). The admin panel's verification-queue and
// report-queue detail screens call this same endpoint (via the relevant
// user_id) to get the same "who is this person" context, rather than
// each screen growing its own bespoke profile join.
type UserDetailResponse struct {
	UserResponse
	Profile      *ProfileSummary      `json:"profile"`
	Subscription *SubscriptionSummary `json:"subscription"`
	Verification *VerificationSummary `json:"verification"`
}

// ProfileSummary is nil in UserDetailResponse when the account never
// completed onboarding (no profiles row yet) — not an error, just an
// incomplete signup, which the admin panel should show as such.
type ProfileSummary struct {
	FullName    *string `json:"full_name"`
	Age         *int    `json:"age"`
	Gender      *string `json:"gender"`
	City        *string `json:"city"`
	State       *string `json:"state"`
	Occupation  *string `json:"occupation"`
	ProfileCode string  `json:"profile_code"`
	PhotoURL    *string `json:"photo_url"`
}

// SubscriptionSummary is nil when the caller has no active, non-expired
// subscription (i.e. they're on the free tier) — mirrors the same
// "active and not yet ended" definition subscriptions.Service.GetMine
// uses for the regular user-facing /subscriptions/me endpoint.
type SubscriptionSummary struct {
	PlanCode string  `json:"plan_code"`
	PlanName string  `json:"plan_name"`
	EndsAt   *string `json:"ends_at"`
}

// VerificationSummary is nil when the user has never submitted an ID
// document at all — distinct from a "pending"/"rejected" status, which
// both have a real submission behind them.
type VerificationSummary struct {
	Status       string  `json:"status"`
	DocumentType string  `json:"document_type"`
	DocumentURL  string  `json:"document_url"`
	ReviewNotes  *string `json:"review_notes"`
	ReviewedAt   *string `json:"reviewed_at"`
}

// SubscriptionRowResponse is one row of GET /admin/subscriptions — a
// real subscription record joined against its user and plan for display,
// not the free-tier "no row at all" case ListUsersMeta's caller sees on
// /subscriptions/me; this endpoint only ever lists rows that exist in
// the subscriptions table.
type SubscriptionRowResponse struct {
	ID       string  `json:"id"`
	UserID   string  `json:"user_id"`
	Phone    *string `json:"phone"`
	Email    *string `json:"email"`
	FullName *string `json:"full_name"`
	PlanCode string  `json:"plan_code"`
	PlanName string  `json:"plan_name"`
	Status   string  `json:"status"`
	StartsAt *string `json:"starts_at"`
	EndsAt   *string `json:"ends_at"`
}

// UnlockAccountRowResponse is one row of GET /admin/unlock-accounts — the
// ₹1 one-time unlock gate's own accounts/revenue view, kept separate from
// SubscriptionRowResponse since the unlock is a front gate, not a plan
// (see internal/unlock and migration 000032). Only ever lists accounts
// that have actually attempted or completed the unlock payment — a user
// who's never seen the paywall has no row here.
type UnlockAccountRowResponse struct {
	ID        string  `json:"id"`
	UserID    string  `json:"user_id"`
	Phone     *string `json:"phone"`
	Email     *string `json:"email"`
	FullName  *string `json:"full_name"`
	AmountINR int64   `json:"amount_inr"`
	Currency  string  `json:"currency"`
	Status    string  `json:"status"` // created, paid, failed
	CreatedAt string  `json:"created_at"`
	PaidAt    *string `json:"paid_at"`
}

// UnlockRevenueSummaryResponse is GET /admin/unlock-accounts/summary — the
// headline numbers for the ₹1 unlock gate, the same way GetRevenue covers
// the plan-based subscription system.
// TotalCreatedAccounts/TotalFailedAccounts turn this summary into a
// conversion funnel alongside TotalPaidAccounts — "43 people started the
// ₹1 checkout, only 31 paid" is the kind of drop-off number this exposes
// that the paid-only total alone can't.
type UnlockRevenueSummaryResponse struct {
	TotalPaidAccounts    int   `json:"total_paid_accounts"`
	TotalCreatedAccounts int   `json:"total_created_accounts"`
	TotalFailedAccounts  int   `json:"total_failed_accounts"`
	TotalRevenueINR      int64 `json:"total_revenue_inr"`
}

// PaymentRowResponse is one row of a user's subscription-payment history,
// part of UserFinanceResponse.
type PaymentRowResponse struct {
	ID          string  `json:"id"`
	PlanName    string  `json:"plan_name"`
	AmountINR   int64   `json:"amount_inr"`
	DiscountINR int64   `json:"discount_inr"`
	Currency    string  `json:"currency"`
	Status      string  `json:"status"`
	CreatedAt   string  `json:"created_at"`
	PaidAt      *string `json:"paid_at"`
}

// UserFinanceResponse is GET /admin/users/:id/finance — a single user's
// full money history across both payment systems (the plan-based
// subscriptions/payments table and the separate ₹1 unlock gate), so a
// support agent doesn't have to cross-reference two different list pages
// to answer "did this person actually pay?".
type UserFinanceResponse struct {
	UnlockPayments []UnlockAccountRowResponse `json:"unlock_payments"`
	Payments       []PaymentRowResponse       `json:"payments"`
}

// RevenueResponse breaks the same "paid, non-refunded payments" figure
// DashboardResponse.RevenueINR already totals down into a per-plan split
// and a monthly time series, for the admin panel's revenue chart —
// TotalINR always equals DashboardResponse.RevenueINR, computed the same
// way, so the two screens can never disagree.
type RevenueResponse struct {
	TotalINR int64               `json:"total_inr"`
	ByPlan   []RevenueByPlanRow  `json:"by_plan"`
	ByMonth  []RevenueByMonthRow `json:"by_month"`
}

type RevenueByPlanRow struct {
	PlanCode      string `json:"plan_code"`
	PlanName      string `json:"plan_name"`
	RevenueINR    int64  `json:"revenue_inr"`
	PaymentsCount int    `json:"payments_count"`
}

type RevenueByMonthRow struct {
	Month      string `json:"month"` // "YYYY-MM"
	RevenueINR int64  `json:"revenue_inr"`
}

type DashboardResponse struct {
	TotalUsers           int   `json:"total_users"`
	ActiveUsers          int   `json:"active_users"`
	SuspendedUsers       int   `json:"suspended_users"`
	NewSignupsToday      int   `json:"new_signups_today"`
	TotalMatches         int   `json:"total_matches"`
	TotalMessages        int   `json:"total_messages"`
	PendingVerifications int   `json:"pending_verifications"`
	PendingReports       int   `json:"pending_reports"`
	ActiveSubscriptions  int   `json:"active_subscriptions"`
	RevenueINR           int64 `json:"revenue_inr"`
	// UnlockRevenueINR/TotalRevenueINR: see Dashboard.UnlockRevenueINR's
	// doc comment — RevenueINR stays the plan-based figure alone (so
	// nothing that already reads it changes meaning), TotalRevenueINR is
	// the new combined-across-both-systems number.
	UnlockRevenueINR int64 `json:"unlock_revenue_inr"`
	TotalRevenueINR  int64 `json:"total_revenue_inr"`
}
