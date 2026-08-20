package payments

import (
	"context"
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

const columns = `
	id, user_id, plan_id, subscription_id, coupon_id, amount_inr, discount_inr, currency,
	razorpay_order_id, razorpay_payment_id, razorpay_signature, status, created_at, paid_at`

func scan(row pgx.Row) (Payment, error) {
	var p Payment
	err := row.Scan(
		&p.ID, &p.UserID, &p.PlanID, &p.SubscriptionID, &p.CouponID, &p.AmountINR, &p.DiscountINR, &p.Currency,
		&p.RazorpayOrderID, &p.RazorpayPaymentID, &p.RazorpaySignature, &p.Status, &p.CreatedAt, &p.PaidAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Payment{}, ErrNotFound
	}
	return p, err
}

func (r *Repository) Create(ctx context.Context, userID, planID, subscriptionID, orderID string, amountINR, discountINR int64, couponID *string) (Payment, error) {
	q := `
		INSERT INTO payments (user_id, plan_id, subscription_id, coupon_id, amount_inr, discount_inr, razorpay_order_id)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING ` + columns
	return scan(r.db.QueryRow(ctx, q, userID, planID, subscriptionID, couponID, amountINR, discountINR, orderID))
}

func (r *Repository) GetByOrderID(ctx context.Context, orderID string) (Payment, error) {
	q := `SELECT ` + columns + ` FROM payments WHERE razorpay_order_id = $1`
	return scan(r.db.QueryRow(ctx, q, orderID))
}

// BeginTx starts a transaction on the same pool subscriptions.Repository
// also shares (both are constructed from the one app-wide dbPool in
// main.go) — see Service.finalizeCapturedPayment, the one place that
// needs payments and subscriptions writes to commit atomically together.
func (r *Repository) BeginTx(ctx context.Context) (pgx.Tx, error) {
	return r.db.Begin(ctx)
}

// GetByOrderIDForUpdate is GetByOrderID's locking counterpart — the
// authoritative status check in Service.finalizeCapturedPayment. Row-locks
// the payment for the duration of the caller's transaction so a second
// concurrent finalize for the same order blocks here until the first
// commits (and then correctly sees status != 'created' and bails out)
// instead of both racing past the status check and double-activating.
func (r *Repository) GetByOrderIDForUpdate(ctx context.Context, tx pgx.Tx, orderID string) (Payment, error) {
	q := `SELECT ` + columns + ` FROM payments WHERE razorpay_order_id = $1 FOR UPDATE`
	return scan(tx.QueryRow(ctx, q, orderID))
}

// MarkPaid must run inside the same transaction as the subscription
// activation it accompanies (tx from BeginTx) — see
// Service.finalizeCapturedPayment. A payment marked paid with its
// subscription still pending (or vice versa) is exactly the divergent
// half-applied state BUG-H04 was about.
func (r *Repository) MarkPaid(ctx context.Context, tx pgx.Tx, id, paymentID, signature string) (Payment, error) {
	q := `
		UPDATE payments
		SET status = 'paid', razorpay_payment_id = $2, razorpay_signature = $3, paid_at = now()
		WHERE id = $1
		RETURNING ` + columns
	return scan(tx.QueryRow(ctx, q, id, paymentID, signature))
}

func (r *Repository) MarkFailed(ctx context.Context, id string) error {
	const q = `UPDATE payments SET status = 'failed' WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	return err
}

func (r *Repository) ListByUser(ctx context.Context, userID string, limit int) ([]Payment, error) {
	q := `SELECT ` + columns + ` FROM payments WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2`
	rows, err := r.db.Query(ctx, q, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []Payment
	for rows.Next() {
		p, err := scan(rows)
		if err != nil {
			return nil, err
		}
		results = append(results, p)
	}
	return results, rows.Err()
}

// PaymentWithPlan is a payment row joined against its plan for display
// purposes (billing history) — plan_id alone isn't something a client can
// show a human, so this carries the plan's code/name alongside it.
type PaymentWithPlan struct {
	Payment
	PlanCode string
	PlanName string
}

func (r *Repository) ListByUserWithPlan(ctx context.Context, userID string, limit int) ([]PaymentWithPlan, error) {
	q := `
		SELECT p.id, p.user_id, p.plan_id, p.subscription_id, p.coupon_id, p.amount_inr, p.discount_inr,
		       p.currency, p.razorpay_order_id, p.razorpay_payment_id, p.razorpay_signature, p.status,
		       p.created_at, p.paid_at, sp.code, sp.name
		FROM payments p
		JOIN subscription_plans sp ON sp.id = p.plan_id
		WHERE p.user_id = $1
		ORDER BY p.created_at DESC
		LIMIT $2`
	rows, err := r.db.Query(ctx, q, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []PaymentWithPlan
	for rows.Next() {
		var p PaymentWithPlan
		if err := rows.Scan(
			&p.ID, &p.UserID, &p.PlanID, &p.SubscriptionID, &p.CouponID, &p.AmountINR, &p.DiscountINR,
			&p.Currency, &p.RazorpayOrderID, &p.RazorpayPaymentID, &p.RazorpaySignature, &p.Status,
			&p.CreatedAt, &p.PaidAt, &p.PlanCode, &p.PlanName,
		); err != nil {
			return nil, err
		}
		results = append(results, p)
	}
	return results, rows.Err()
}
