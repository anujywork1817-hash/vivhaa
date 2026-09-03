package admin

import "time"

type User struct {
	ID            string
	Phone         *string
	Email         *string
	PhoneVerified bool
	EmailVerified bool
	Status        string
	Role          string
	LastLoginAt   *time.Time
	CreatedAt     time.Time
}

// ReportedUserRow is one row of the trust & safety "most reported"
// list — a user aggregated across every report filed against them,
// regardless of that report's individual status (a dismissed report
// still counts toward "how many people have flagged this account").
type ReportedUserRow struct {
	UserID         string
	Phone          *string
	Email          *string
	FullName       *string
	ReportCount    int
	LastReportedAt time.Time
}

// BlockedUserRow is the "most blocked" counterpart — an account many
// distinct other users have chosen to block is a real-world reputation
// signal reports alone can miss (nobody has to explain why they blocked
// someone).
type BlockedUserRow struct {
	UserID     string
	Phone      *string
	Email      *string
	FullName   *string
	BlockCount int
}

// SharedDeviceAccount is one account sharing a push-notification device
// token with at least one other account — see SharedDeviceGroup.
type SharedDeviceAccount struct {
	UserID   string
	Phone    *string
	Email    *string
	FullName *string
}

// SharedDeviceGroup is every account registered against the same device
// token — a device legitimately reused for multiple real family members'
// accounts looks identical to one operator running several fake profiles
// from a single phone, so this is a signal to investigate, not a verdict.
type SharedDeviceGroup struct {
	Token    string
	Accounts []SharedDeviceAccount
}

type SubscriptionRow struct {
	ID       string
	UserID   string
	Phone    *string
	Email    *string
	FullName *string
	PlanCode string
	PlanName string
	Status   string
	StartsAt *time.Time
	EndsAt   *time.Time
}

// UnlockAccountRow mirrors unlock_payments joined against its user/profile
// for display — see UnlockAccountRowResponse's doc comment for why this is
// separate from SubscriptionRow.
type UnlockAccountRow struct {
	ID        string
	UserID    string
	Phone     *string
	Email     *string
	FullName  *string
	AmountINR int64
	Currency  string
	Status    string
	CreatedAt time.Time
	PaidAt    *time.Time
}

// PaymentRow is one row of a user's subscription-payment history —
// distinct from UnlockAccountRow, which covers the separate ₹1 gate.
type PaymentRow struct {
	ID          string
	PlanName    string
	AmountINR   int64
	DiscountINR int64
	Currency    string
	Status      string
	CreatedAt   time.Time
	PaidAt      *time.Time
}

type RevenueByPlan struct {
	PlanCode      string
	PlanName      string
	RevenueINR    int64
	PaymentsCount int
}

type RevenueByMonth struct {
	Month      string
	RevenueINR int64
}

type Dashboard struct {
	TotalUsers           int
	ActiveUsers          int
	SuspendedUsers       int
	NewSignupsToday      int
	TotalMatches         int
	TotalMessages        int
	PendingVerifications int
	PendingReports       int
	ActiveSubscriptions  int
	RevenueINR           int64
	// UnlockRevenueINR is the separate ₹1 unlock-gate's own revenue —
	// summed alongside RevenueINR into DashboardResponse.TotalRevenueINR
	// so the dashboard shows one true total instead of the plan-based
	// figure alone.
	UnlockRevenueINR int64
}
