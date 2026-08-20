package devices

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

// Register records a token for a user, or moves it to them if another
// account had it. FCM hands the same token to whoever installs on that
// device next, so an upsert keyed on the token (rather than an insert) is
// what stops a previous owner's notifications following the hardware.
func (r *Repository) Register(ctx context.Context, userID, token, platform string) error {
	const q = `
		INSERT INTO device_tokens (user_id, token, platform)
		VALUES ($1, $2, $3)
		ON CONFLICT (token) DO UPDATE
		SET user_id = EXCLUDED.user_id,
		    platform = EXCLUDED.platform,
		    updated_at = now()`
	_, err := r.db.Exec(ctx, q, userID, token, platform)
	return err
}

// Unregister drops a single token — used on sign-out so a shared device
// stops receiving the previous user's notifications.
func (r *Repository) Unregister(ctx context.Context, userID, token string) error {
	const q = `DELETE FROM device_tokens WHERE user_id = $1 AND token = $2`
	_, err := r.db.Exec(ctx, q, userID, token)
	return err
}

// ListTokens returns every token registered to a user, across devices.
func (r *Repository) ListTokens(ctx context.Context, userID string) ([]string, error) {
	const q = `SELECT token FROM device_tokens WHERE user_id = $1`
	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		tokens = append(tokens, t)
	}
	return tokens, rows.Err()
}

// DeleteTokens removes tokens FCM has reported as permanently invalid
// (uninstalled app, expired registration), so they aren't retried forever.
func (r *Repository) DeleteTokens(ctx context.Context, tokens []string) error {
	if len(tokens) == 0 {
		return nil
	}
	const q = `DELETE FROM device_tokens WHERE token = ANY($1)`
	_, err := r.db.Exec(ctx, q, tokens)
	return err
}
