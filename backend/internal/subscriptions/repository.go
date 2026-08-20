package subscriptions

import (
	"context"
	"encoding/json"
	"errors"

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

func scanPlan(row pgx.Row) (Plan, error) {
	var p Plan
	var rawFeatures []byte
	err := row.Scan(&p.ID, &p.Code, &p.Name, &p.PriceINR, &p.DurationDays, &rawFeatures, &p.IsActive, &p.TierRank)
	if errors.Is(err, pgx.ErrNoRows) {
		return Plan{}, ErrNotFound
	}
	if err != nil {
		return Plan{}, err
	}
	if len(rawFeatures) > 0 {
		if err := json.Unmarshal(rawFeatures, &p.Features); err != nil {
			return Plan{}, err
		}
	}
	return p, nil
}

const planColumns = `id, code, name, price_inr, duration_days, features, is_active, tier_rank`

func (r *Repository) ListActivePlans(ctx context.Context) ([]Plan, error) {
	q := `SELECT ` + planColumns + ` FROM subscription_plans WHERE is_active = TRUE ORDER BY tier_rank ASC`
	rows, err := r.db.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var plans []Plan
	for rows.Next() {
		p, err := scanPlan(rows)
		if err != nil {
			return nil, err
		}
		plans = append(plans, p)
	}
	return plans, rows.Err()
}

func (r *Repository) GetPlanByCode(ctx context.Context, code string) (Plan, error) {
	q := `SELECT ` + planColumns + ` FROM subscription_plans WHERE code = $1 AND is_active = TRUE`
	return scanPlan(r.db.QueryRow(ctx, q, code))
}

func (r *Repository) GetPlanByID(ctx context.Context, id string) (Plan, error) {
	q := `SELECT ` + planColumns + ` FROM subscription_plans WHERE id = $1`
	return scanPlan(r.db.QueryRow(ctx, q, id))
}

func (r *Repository) CreatePending(ctx context.Context, userID, planID string) (Subscription, error) {
	const q = `
		INSERT INTO subscriptions (user_id, plan_id, status)
		VALUES ($1, $2, 'pending')
		RETURNING id, user_id, plan_id, status, starts_at, ends_at, created_at`
	var s Subscription
	err := r.db.QueryRow(ctx, q, userID, planID).Scan(&s.ID, &s.UserID, &s.PlanID, &s.Status, &s.StartsAt, &s.EndsAt, &s.CreatedAt)
	return s, err
}

// Activate runs inside the caller's transaction (tx from
// payments.Repository.BeginTx — both repositories share the app-wide
// dbPool, so a pgx.Tx begun on either works for both) so it commits
// atomically with the payments.MarkPaid call alongside it. See
// payments.Service.finalizeCapturedPayment.
func (r *Repository) Activate(ctx context.Context, tx pgx.Tx, id string, durationDays int) (Subscription, error) {
	const q = `
		UPDATE subscriptions
		SET status = 'active', starts_at = now(), ends_at = now() + make_interval(days => $2)
		WHERE id = $1
		RETURNING id, user_id, plan_id, status, starts_at, ends_at, created_at`
	var s Subscription
	err := tx.QueryRow(ctx, q, id, durationDays).Scan(&s.ID, &s.UserID, &s.PlanID, &s.Status, &s.StartsAt, &s.EndsAt, &s.CreatedAt)
	return s, err
}

// GetActiveByUserID returns the caller's current active, non-expired
// subscription, if any.
func (r *Repository) GetActiveByUserID(ctx context.Context, userID string) (Subscription, error) {
	const q = `
		SELECT id, user_id, plan_id, status, starts_at, ends_at, created_at
		FROM subscriptions
		WHERE user_id = $1 AND status = 'active' AND ends_at > now()
		ORDER BY created_at DESC LIMIT 1`
	var s Subscription
	err := r.db.QueryRow(ctx, q, userID).Scan(&s.ID, &s.UserID, &s.PlanID, &s.Status, &s.StartsAt, &s.EndsAt, &s.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Subscription{}, ErrNotFound
	}
	return s, err
}

func (r *Repository) GetByID(ctx context.Context, id string) (Subscription, error) {
	const q = `SELECT id, user_id, plan_id, status, starts_at, ends_at, created_at FROM subscriptions WHERE id = $1`
	var s Subscription
	err := r.db.QueryRow(ctx, q, id).Scan(&s.ID, &s.UserID, &s.PlanID, &s.Status, &s.StartsAt, &s.EndsAt, &s.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Subscription{}, ErrNotFound
	}
	return s, err
}

// ExpireEnded flips any subscription whose end date has passed but is
// still marked active — run by cmd/scheduler as a daily batch job rather
// than checked lazily on every read.
func (r *Repository) ExpireEnded(ctx context.Context) (int64, error) {
	const q = `UPDATE subscriptions SET status = 'expired' WHERE status = 'active' AND ends_at <= now()`
	tag, err := r.db.Exec(ctx, q)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}
