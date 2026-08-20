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

func (r *Repository) IncrementUsage(ctx context.Context, id string) error {
	const q = `UPDATE coupons SET used_count = used_count + 1 WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	return err
}
