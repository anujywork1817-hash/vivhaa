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
}
