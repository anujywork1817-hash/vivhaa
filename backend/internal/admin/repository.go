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

	return d, nil
}
