package unlock

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
	id, user_id, amount_inr, currency, razorpay_order_id, razorpay_payment_id,
	razorpay_signature, status, created_at, paid_at`

func scan(row pgx.Row) (Payment, error) {
	var p Payment
	err := row.Scan(
		&p.ID, &p.UserID, &p.AmountINR, &p.Currency, &p.RazorpayOrderID, &p.RazorpayPaymentID,
		&p.RazorpaySignature, &p.Status, &p.CreatedAt, &p.PaidAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Payment{}, ErrNotFound
	}
	return p, err
}

func (r *Repository) Create(ctx context.Context, userID, orderID string, amountINR int64, currency string) (Payment, error) {
	q := `
		INSERT INTO unlock_payments (user_id, amount_inr, currency, razorpay_order_id)
		VALUES ($1, $2, $3, $4)
		RETURNING ` + columns
	return scan(r.db.QueryRow(ctx, q, userID, amountINR, currency, orderID))
}

func (r *Repository) GetByOrderID(ctx context.Context, orderID string) (Payment, error) {
	q := `SELECT ` + columns + ` FROM unlock_payments WHERE razorpay_order_id = $1`
	return scan(r.db.QueryRow(ctx, q, orderID))
}

// GetLatestPendingByUserID returns the caller's most recent still-"created"
// unlock order, if any — Checkout reuses it instead of creating a fresh
// Razorpay order every time the paywall screen mounts.
func (r *Repository) GetLatestPendingByUserID(ctx context.Context, userID string) (Payment, error) {
	q := `SELECT ` + columns + ` FROM unlock_payments WHERE user_id = $1 AND status = 'created' ORDER BY created_at DESC LIMIT 1`
	return scan(r.db.QueryRow(ctx, q, userID))
}

// BeginTx starts a transaction on the same pool every other repository in
// this app shares — see Service.finalizeCapturedPayment, mirroring
// payments.Repository.BeginTx / GetByOrderIDForUpdate exactly.
func (r *Repository) BeginTx(ctx context.Context) (pgx.Tx, error) {
	return r.db.Begin(ctx)
}

// GetByOrderIDForUpdate row-locks the payment for the duration of the
// caller's transaction, the same concurrency guard
// payments.Repository.GetByOrderIDForUpdate provides for the plan-based
// flow — see its doc comment for why this matters (two concurrent
// finalize calls for the same order must not both pass the status check).
func (r *Repository) GetByOrderIDForUpdate(ctx context.Context, tx pgx.Tx, orderID string) (Payment, error) {
	q := `SELECT ` + columns + ` FROM unlock_payments WHERE razorpay_order_id = $1 FOR UPDATE`
	return scan(tx.QueryRow(ctx, q, orderID))
}

func (r *Repository) MarkPaid(ctx context.Context, tx pgx.Tx, id, paymentID, signature string) (Payment, error) {
	q := `
		UPDATE unlock_payments
		SET status = 'paid', razorpay_payment_id = $2, razorpay_signature = $3, paid_at = now()
		WHERE id = $1
		RETURNING ` + columns
	return scan(tx.QueryRow(ctx, q, id, paymentID, signature))
}

func (r *Repository) MarkFailed(ctx context.Context, id string) error {
	const q = `UPDATE unlock_payments SET status = 'failed' WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	return err
}
