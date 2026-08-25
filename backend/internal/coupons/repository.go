package coupons

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

const columns = `id, code, description, discount_type, discount_value, max_uses, used_count, valid_from, valid_until, is_active`

func (r *Repository) GetByCode(ctx context.Context, code string) (Coupon, error) {
	q := `SELECT ` + columns + ` FROM coupons WHERE code = $1`
	var c Coupon
	err := r.db.QueryRow(ctx, q, code).Scan(
		&c.ID, &c.Code, &c.Description, &c.DiscountType, &c.DiscountValue, &c.MaxUses, &c.UsedCount, &c.ValidFrom, &c.ValidUntil, &c.IsActive)
	if errors.Is(err, pgx.ErrNoRows) {
		return Coupon{}, ErrNotFound
	}
	return c, err
}

// IncrementUsage atomically reserves one use of the coupon, only
// succeeding while under max_uses — the UPDATE's WHERE clause and
// increment happen as a single atomic statement, so two concurrent
// callers can't both read used_count < max_uses and both increment,
// oversubscribing a max-uses=1 coupon (the previous check-then-increment
// across two separate calls had exactly that race). Returns
// coupons.ErrExhausted if no row matched (limit already reached or hit by
// a concurrent caller first).
func (r *Repository) IncrementUsage(ctx context.Context, id string) error {
	const q = `
		UPDATE coupons SET used_count = used_count + 1
		WHERE id = $1 AND (max_uses IS NULL OR used_count < max_uses)`
	tag, err := r.db.Exec(ctx, q, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrExhausted
	}
	return nil
}

// DecrementUsage releases a reservation IncrementUsage made, when the
// checkout that reserved it doesn't end up completing (order-creation
// failure, a DB write failure, ...) — without this, an abandoned checkout
// would permanently burn one use of the coupon for nothing.
func (r *Repository) DecrementUsage(ctx context.Context, id string) error {
	const q = `UPDATE coupons SET used_count = used_count - 1 WHERE id = $1 AND used_count > 0`
	_, err := r.db.Exec(ctx, q, id)
	return err
}
