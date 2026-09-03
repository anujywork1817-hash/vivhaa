package admin

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("not found")

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

const userColumns = `id, phone, email, phone_verified, email_verified, status, role, last_login_at, created_at`

func scanUser(row pgx.Row) (User, error) {
	var u User
	err := row.Scan(&u.ID, &u.Phone, &u.Email, &u.PhoneVerified, &u.EmailVerified, &u.Status, &u.Role, &u.LastLoginAt, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrNotFound
	}
	return u, err
}

type ListUsersFilter struct {
	Status *string
	Role   *string
	Search *string
	Page   int
	Limit  int
}

func (r *Repository) ListUsers(ctx context.Context, f ListUsersFilter) ([]User, int, error) {
	where := []string{"deleted_at IS NULL"}
	args := []interface{}{}

	add := func(cond string, val interface{}) {
		args = append(args, val)
		where = append(where, fmt.Sprintf(cond, len(args)))
	}

	if f.Status != nil {
		add("status = $%d", *f.Status)
	}
	if f.Role != nil {
		add("role = $%d", *f.Role)
	}
	if f.Search != nil {
		args = append(args, *f.Search)
		n := len(args)
		where = append(where, fmt.Sprintf("(phone ILIKE '%%' || $%d || '%%' OR email ILIKE '%%' || $%d || '%%')", n, n))
	}

	whereClause := strings.Join(where, " AND ")

	var total int
	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE `+whereClause, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	limit := f.Limit
	offset := (f.Page - 1) * f.Limit
	args = append(args, limit, offset)

	q := fmt.Sprintf(`SELECT %s FROM users WHERE %s ORDER BY created_at DESC LIMIT $%d OFFSET $%d`,
		userColumns, whereClause, len(args)-1, len(args))

	rows, err := r.db.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, 0, err
		}
		users = append(users, u)
	}
	return users, total, rows.Err()
}

func (r *Repository) GetUserByID(ctx context.Context, id string) (User, error) {
	q := `SELECT ` + userColumns + ` FROM users WHERE id = $1 AND deleted_at IS NULL`
	return scanUser(r.db.QueryRow(ctx, q, id))
}

func (r *Repository) UpdateUserStatus(ctx context.Context, id, status string) (User, error) {
	q := `UPDATE users SET status = $2, updated_at = now() WHERE id = $1 AND deleted_at IS NULL RETURNING ` + userColumns
	return scanUser(r.db.QueryRow(ctx, q, id, status))
}

// ListSubscriptions joins subscriptions against their user (for a
// display identifier) and plan (for a readable code/name), optionally
// filtered by status — mirrors ListUsers' filter+paginate shape.
func (r *Repository) ListSubscriptions(ctx context.Context, status *string, limit, offset int) ([]SubscriptionRow, int, error) {
	where := "1=1"
	args := []interface{}{}
	if status != nil {
		args = append(args, *status)
		where = fmt.Sprintf("s.status = $%d", len(args))
	}

	var total int
	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM subscriptions s WHERE `+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	args = append(args, limit, offset)
	q := fmt.Sprintf(`
		SELECT s.id, s.user_id, u.phone, u.email, p.full_name, sp.code, sp.name, s.status, s.starts_at, s.ends_at
		FROM subscriptions s
		JOIN users u ON u.id = s.user_id
		JOIN subscription_plans sp ON sp.id = s.plan_id
		LEFT JOIN profiles p ON p.user_id = s.user_id
		WHERE %s
		ORDER BY s.created_at DESC
		LIMIT $%d OFFSET $%d`, where, len(args)-1, len(args))

	rows, err := r.db.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var out []SubscriptionRow
	for rows.Next() {
		var s SubscriptionRow
		if err := rows.Scan(&s.ID, &s.UserID, &s.Phone, &s.Email, &s.FullName, &s.PlanCode, &s.PlanName, &s.Status, &s.StartsAt, &s.EndsAt); err != nil {
			return nil, 0, err
		}
		out = append(out, s)
	}
	return out, total, rows.Err()
}

// ListUnlockAccounts joins unlock_payments against its user (for a display
// identifier) and profile (for a name), optionally filtered by status —
// mirrors ListSubscriptions' filter+paginate shape, for the separate
// ₹1-unlock-gate accounts/revenue view.
func (r *Repository) ListUnlockAccounts(ctx context.Context, status *string, limit, offset int) ([]UnlockAccountRow, int, error) {
	where := "1=1"
	args := []interface{}{}
	if status != nil {
		args = append(args, *status)
		where = fmt.Sprintf("up.status = $%d", len(args))
	}

	var total int
	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM unlock_payments up WHERE `+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	args = append(args, limit, offset)
	q := fmt.Sprintf(`
		SELECT up.id, up.user_id, u.phone, u.email, p.full_name, up.amount_inr, up.currency, up.status, up.created_at, up.paid_at
		FROM unlock_payments up
		JOIN users u ON u.id = up.user_id
		LEFT JOIN profiles p ON p.user_id = up.user_id
		WHERE %s
		ORDER BY up.created_at DESC
		LIMIT $%d OFFSET $%d`, where, len(args)-1, len(args))

	rows, err := r.db.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var out []UnlockAccountRow
	for rows.Next() {
		var a UnlockAccountRow
		if err := rows.Scan(&a.ID, &a.UserID, &a.Phone, &a.Email, &a.FullName, &a.AmountINR, &a.Currency, &a.Status, &a.CreatedAt, &a.PaidAt); err != nil {
			return nil, 0, err
		}
		out = append(out, a)
	}
	return out, total, rows.Err()
}

// GetUnlockRevenueSummary reports the headline numbers for the ₹1 unlock
// gate — how many accounts have actually paid (and the revenue that
// represents), plus how many started checkout ('created') or failed it,
// turning this into a conversion funnel rather than just a revenue total.
// Only 'paid' rows count toward revenue; a 'created' (checkout started,
// never completed) or 'failed' row is not revenue.
func (r *Repository) GetUnlockRevenueSummary(ctx context.Context) (paid int, created int, failed int, revenueINR int64, err error) {
	err = r.db.QueryRow(ctx, `
		SELECT
			COUNT(*) FILTER (WHERE status = 'paid'),
			COUNT(*) FILTER (WHERE status = 'created'),
			COUNT(*) FILTER (WHERE status = 'failed'),
			COALESCE(SUM(amount_inr) FILTER (WHERE status = 'paid'), 0)
		FROM unlock_payments`).Scan(&paid, &created, &failed, &revenueINR)
	return paid, created, failed, revenueINR, err
}

// GetUnlockPaymentsForUser is ListUnlockAccounts narrowed to one user, for
// the per-user finance view — a user with no unlock attempt at all gets
// an empty slice, not an error.
func (r *Repository) GetUnlockPaymentsForUser(ctx context.Context, userID string) ([]UnlockAccountRow, error) {
	q := `
		SELECT up.id, up.user_id, u.phone, u.email, p.full_name, up.amount_inr, up.currency, up.status, up.created_at, up.paid_at
		FROM unlock_payments up
		JOIN users u ON u.id = up.user_id
		LEFT JOIN profiles p ON p.user_id = up.user_id
		WHERE up.user_id = $1
		ORDER BY up.created_at DESC`
	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []UnlockAccountRow
	for rows.Next() {
		var a UnlockAccountRow
		if err := rows.Scan(&a.ID, &a.UserID, &a.Phone, &a.Email, &a.FullName, &a.AmountINR, &a.Currency, &a.Status, &a.CreatedAt, &a.PaidAt); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// GetPaymentsForUser lists one user's subscription-payment history
// (payments table), newest first — the plan-based counterpart to
// GetUnlockPaymentsForUser.
func (r *Repository) GetPaymentsForUser(ctx context.Context, userID string) ([]PaymentRow, error) {
	q := `
		SELECT pay.id, sp.name, pay.amount_inr, pay.discount_inr, pay.currency, pay.status, pay.created_at, pay.paid_at
		FROM payments pay
		JOIN subscription_plans sp ON sp.id = pay.plan_id
		WHERE pay.user_id = $1
		ORDER BY pay.created_at DESC`
	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []PaymentRow
	for rows.Next() {
		var p PaymentRow
		if err := rows.Scan(&p.ID, &p.PlanName, &p.AmountINR, &p.DiscountINR, &p.Currency, &p.Status, &p.CreatedAt, &p.PaidAt); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// GetRevenueByPlan and GetRevenueByMonth both count only 'paid' payments,
// net of any discount — the same definition GetDashboard's single
// RevenueINR total already uses, just grouped two different ways.
func (r *Repository) GetRevenueByPlan(ctx context.Context) ([]RevenueByPlan, error) {
	q := `
		SELECT sp.code, sp.name, COALESCE(SUM(pay.amount_inr - pay.discount_inr), 0), COUNT(*)
		FROM payments pay
		JOIN subscription_plans sp ON sp.id = pay.plan_id
		WHERE pay.status = 'paid'
		GROUP BY sp.code, sp.name
		ORDER BY 3 DESC`
	rows, err := r.db.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []RevenueByPlan
	for rows.Next() {
		var rp RevenueByPlan
		if err := rows.Scan(&rp.PlanCode, &rp.PlanName, &rp.RevenueINR, &rp.PaymentsCount); err != nil {
			return nil, err
		}
		out = append(out, rp)
	}
	return out, rows.Err()
}

// GetRevenueByMonth covers the trailing 12 months (by paid_at, since
// that's when the money actually moved, not when the order was created).
func (r *Repository) GetRevenueByMonth(ctx context.Context) ([]RevenueByMonth, error) {
	q := `
		SELECT to_char(paid_at, 'YYYY-MM'), COALESCE(SUM(amount_inr - discount_inr), 0)
		FROM payments
		WHERE status = 'paid' AND paid_at >= now() - interval '12 months'
		GROUP BY 1
		ORDER BY 1 ASC`
	rows, err := r.db.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []RevenueByMonth
	for rows.Next() {
		var rm RevenueByMonth
		if err := rows.Scan(&rm.Month, &rm.RevenueINR); err != nil {
			return nil, err
		}
		out = append(out, rm)
	}
	return out, rows.Err()
}

// GetMostReportedUsers aggregates every report ever filed (any status —
// a dismissed report still counts toward "how many people flagged this
// account"), grouped by the reported user, worst offenders first.
func (r *Repository) GetMostReportedUsers(ctx context.Context, limit int) ([]ReportedUserRow, error) {
	q := `
		SELECT r.reported_user_id, u.phone, u.email, p.full_name, COUNT(*), MAX(r.created_at)
		FROM reports r
		JOIN users u ON u.id = r.reported_user_id
		LEFT JOIN profiles p ON p.user_id = r.reported_user_id
		GROUP BY r.reported_user_id, u.phone, u.email, p.full_name
		ORDER BY COUNT(*) DESC, MAX(r.created_at) DESC
		LIMIT $1`
	rows, err := r.db.Query(ctx, q, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []ReportedUserRow
	for rows.Next() {
		var row ReportedUserRow
		if err := rows.Scan(&row.UserID, &row.Phone, &row.Email, &row.FullName, &row.ReportCount, &row.LastReportedAt); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

// GetMostBlockedUsers is GetMostReportedUsers' counterpart for
// blocked_users — a reputation signal that needs no explanation from the
// blocker, unlike a report.
func (r *Repository) GetMostBlockedUsers(ctx context.Context, limit int) ([]BlockedUserRow, error) {
	q := `
		SELECT b.blocked_user_id, u.phone, u.email, p.full_name, COUNT(*)
		FROM blocked_users b
		JOIN users u ON u.id = b.blocked_user_id
		LEFT JOIN profiles p ON p.user_id = b.blocked_user_id
		GROUP BY b.blocked_user_id, u.phone, u.email, p.full_name
		ORDER BY COUNT(*) DESC
		LIMIT $1`
	rows, err := r.db.Query(ctx, q, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []BlockedUserRow
	for rows.Next() {
		var row BlockedUserRow
		if err := rows.Scan(&row.UserID, &row.Phone, &row.Email, &row.FullName, &row.BlockCount); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

// GetSharedDeviceGroups returns, for every push-notification device
// token registered against 2+ distinct accounts, the full list of
// accounts sharing it — the raw (token, account) pairs; grouping into
// SharedDeviceGroup happens in the service layer since SQL has no clean
// way to nest a variable-length join result per group here without a
// JSON aggregate this codebase doesn't otherwise use.
func (r *Repository) GetSharedDeviceGroups(ctx context.Context, limit int) ([]struct {
	Token   string
	Account SharedDeviceAccount
}, error) {
	q := `
		SELECT dt.token, u.id, u.phone, u.email, p.full_name
		FROM device_tokens dt
		JOIN users u ON u.id = dt.user_id
		LEFT JOIN profiles p ON p.user_id = u.id
		WHERE dt.token IN (
			SELECT token FROM device_tokens GROUP BY token HAVING COUNT(DISTINCT user_id) > 1
		)
		ORDER BY dt.token
		LIMIT $1`
	rows, err := r.db.Query(ctx, q, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []struct {
		Token   string
		Account SharedDeviceAccount
	}
	for rows.Next() {
		var row struct {
			Token   string
			Account SharedDeviceAccount
		}
		if err := rows.Scan(&row.Token, &row.Account.UserID, &row.Account.Phone, &row.Account.Email, &row.Account.FullName); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

func (r *Repository) GetDashboard(ctx context.Context) (Dashboard, error) {
	var d Dashboard

	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE deleted_at IS NULL`).Scan(&d.TotalUsers); err != nil {
		return Dashboard{}, err
	}
	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE status = 'active' AND deleted_at IS NULL`).Scan(&d.ActiveUsers); err != nil {
		return Dashboard{}, err
	}
	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE status = 'suspended' AND deleted_at IS NULL`).Scan(&d.SuspendedUsers); err != nil {
		return Dashboard{}, err
	}

	today := time.Now().UTC().Truncate(24 * time.Hour)
	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE created_at >= $1`, today).Scan(&d.NewSignupsToday); err != nil {
		return Dashboard{}, err
	}

	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM interests WHERE status = 'accepted'`).Scan(&d.TotalMatches); err != nil {
		return Dashboard{}, err
	}
	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM chat_messages`).Scan(&d.TotalMessages); err != nil {
		return Dashboard{}, err
	}
	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM verifications WHERE status = 'pending'`).Scan(&d.PendingVerifications); err != nil {
		return Dashboard{}, err
	}
	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM reports WHERE status = 'pending'`).Scan(&d.PendingReports); err != nil {
		return Dashboard{}, err
	}
	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM subscriptions WHERE status = 'active' AND ends_at > now()`).Scan(&d.ActiveSubscriptions); err != nil {
		return Dashboard{}, err
	}
	if err := r.db.QueryRow(ctx, `SELECT COALESCE(SUM(amount_inr - discount_inr), 0) FROM payments WHERE status = 'paid'`).Scan(&d.RevenueINR); err != nil {
		return Dashboard{}, err
	}
	if err := r.db.QueryRow(ctx, `SELECT COALESCE(SUM(amount_inr), 0) FROM unlock_payments WHERE status = 'paid'`).Scan(&d.UnlockRevenueINR); err != nil {
		return Dashboard{}, err
	}

	return d, nil
}
