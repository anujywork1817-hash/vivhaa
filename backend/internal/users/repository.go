package users

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"matrimony-backend/internal/queue"
)

var ErrNotFound = errors.New("not found")

type User struct {
	ID            string    `json:"id"`
	Phone         *string   `json:"phone"`
	Email         *string   `json:"email"`
	PhoneVerified bool      `json:"phone_verified"`
	EmailVerified bool      `json:"email_verified"`
	Status        string    `json:"status"`
	Role          string    `json:"role"`
	CreatedAt     time.Time `json:"created_at"`
}

type Repository struct {
	db        *pgxpool.Pool
	publisher *queue.Publisher
}

func NewRepository(db *pgxpool.Pool, publisher *queue.Publisher) *Repository {
	return &Repository{db: db, publisher: publisher}
}

func (r *Repository) GetByID(ctx context.Context, id string) (User, error) {
	const q = `
		SELECT id, phone, email, phone_verified, email_verified, status, role, created_at
		FROM users WHERE id = $1 AND deleted_at IS NULL`
	var u User
	err := r.db.QueryRow(ctx, q, id).Scan(
		&u.ID, &u.Phone, &u.Email, &u.PhoneVerified, &u.EmailVerified, &u.Status, &u.Role, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrNotFound
	}
	return u, err
}

// DeleteAccount soft-deletes the user (auth.Repository's own lookups
// already exclude deleted_at IS NULL rows, so this alone blocks any future
// login), revokes every refresh token they hold so already-issued sessions
// stop working immediately rather than at their natural expiry, and flips
// their profile private so it drops out of search/match results the same
// way any other private profile would — there's no separate "deleted
// profile" state, and private already means "hidden from everyone but the
// owner", which is exactly what's wanted here.
func (r *Repository) DeleteAccount(ctx context.Context, userID string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx,
		`UPDATE users SET status = 'deleted', deleted_at = now(), updated_at = now()
		 WHERE id = $1 AND deleted_at IS NULL`, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}

	if _, err := tx.Exec(ctx,
		`UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL`, userID); err != nil {
		return err
	}

	var profileID string
	err = tx.QueryRow(ctx,
		`UPDATE profiles SET visibility = 'private', updated_at = now() WHERE user_id = $1 RETURNING id`,
		userID).Scan(&profileID)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}

	if err := tx.Commit(ctx); err != nil {
		return err
	}

	// Every other profile mutation flows through profiles.Service's own
	// publishUpdated, which reindexes in Elasticsearch — this path bypassed
	// that entirely (a raw SQL UPDATE, no publisher at all), so a deleted
	// account's profile stayed fully searchable by name/city/community
	// indefinitely even though every Postgres-backed surface already hid
	// it. profileID is empty when the user never created a profile at all
	// (nothing to reindex then).
	if profileID != "" {
		_ = r.publisher.PublishProfileUpdated(ctx, queue.ProfileUpdatedEvent{ProfileID: profileID, UserID: userID})
	}

	return nil
}

// IsUnlocked reports whether userID has completed the one-time ₹1 unlock
// payment (see internal/unlock) — separate from and unrelated to the
// subscription/premium tier system.
func (r *Repository) IsUnlocked(ctx context.Context, userID string) (bool, error) {
	const q = `SELECT unlocked_at IS NOT NULL FROM users WHERE id = $1 AND deleted_at IS NULL`
	var unlocked bool
	err := r.db.QueryRow(ctx, q, userID).Scan(&unlocked)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, ErrNotFound
	}
	return unlocked, err
}

// MarkUnlocked permanently unlocks userID — idempotent: a second call
// after the first is a harmless no-op, which is what makes it safe for
// internal/unlock's Verify to call unconditionally once a payment is
// confirmed captured, even under a retried webhook delivery.
func (r *Repository) MarkUnlocked(ctx context.Context, userID string) error {
	const q = `UPDATE users SET unlocked_at = COALESCE(unlocked_at, now()) WHERE id = $1 AND deleted_at IS NULL`
	tag, err := r.db.Exec(ctx, q, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
