package blocked

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNotFound      = errors.New("not found")
	ErrAlreadyExists = errors.New("profile already blocked")
)

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Create(ctx context.Context, userID, blockedUserID string) (BlockedUser, error) {
	const q = `
		INSERT INTO blocked_users (user_id, blocked_user_id)
		VALUES ($1, $2)
		RETURNING id, user_id, blocked_user_id, created_at`
	var b BlockedUser
	err := r.db.QueryRow(ctx, q, userID, blockedUserID).Scan(&b.ID, &b.UserID, &b.BlockedUserID, &b.CreatedAt)
	if isUniqueViolation(err) {
		return BlockedUser{}, ErrAlreadyExists
	}
	return b, err
}

func (r *Repository) Delete(ctx context.Context, userID, blockedUserID string) error {
	const q = `DELETE FROM blocked_users WHERE user_id = $1 AND blocked_user_id = $2`
	tag, err := r.db.Exec(ctx, q, userID, blockedUserID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) List(ctx context.Context, userID string) ([]BlockedWithProfile, error) {
	const q = `
		SELECT b.id, b.user_id, b.blocked_user_id, b.created_at,
		       p.id, p.full_name, p.city,
		       (SELECT url FROM profile_photos pp WHERE pp.profile_id = p.id ORDER BY pp.is_primary DESC, pp.sort_order ASC LIMIT 1)
		FROM blocked_users b
		JOIN profiles p ON p.user_id = b.blocked_user_id
		WHERE b.user_id = $1
		ORDER BY b.created_at DESC`
	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []BlockedWithProfile
	for rows.Next() {
		var bwp BlockedWithProfile
		if err := rows.Scan(
			&bwp.ID, &bwp.UserID, &bwp.BlockedUserID, &bwp.CreatedAt,
			&bwp.ProfileID, &bwp.FullName, &bwp.City, &bwp.PhotoURL,
		); err != nil {
			return nil, err
		}
		results = append(results, bwp)
	}
	return results, rows.Err()
}

// IsBlocked reports whether either user has blocked the other.
func (r *Repository) IsBlocked(ctx context.Context, userA, userB string) (bool, error) {
	const q = `
		SELECT EXISTS (
			SELECT 1 FROM blocked_users
			WHERE (user_id = $1 AND blocked_user_id = $2) OR (user_id = $2 AND blocked_user_id = $1)
		)`
	var exists bool
	err := r.db.QueryRow(ctx, q, userA, userB).Scan(&exists)
	return exists, err
}

// Directions reports the block relationship between two users
// independently in each direction, so callers (profile detail) can show
// "you blocked them" vs. "they blocked you" instead of one merged flag.
func (r *Repository) Directions(ctx context.Context, userA, userB string) (aBlockedB bool, bBlockedA bool, err error) {
	const q = `
		SELECT
			EXISTS (SELECT 1 FROM blocked_users WHERE user_id = $1 AND blocked_user_id = $2),
			EXISTS (SELECT 1 FROM blocked_users WHERE user_id = $2 AND blocked_user_id = $1)`
	err = r.db.QueryRow(ctx, q, userA, userB).Scan(&aBlockedB, &bBlockedA)
	return aBlockedB, bBlockedA, err
}

// ListBlockedUserIDs returns every user ID that userID has blocked or has
// been blocked by — used to exclude both directions from search/matches.
func (r *Repository) ListBlockedUserIDs(ctx context.Context, userID string) ([]string, error) {
	const q = `
		SELECT blocked_user_id FROM blocked_users WHERE user_id = $1
		UNION
		SELECT user_id FROM blocked_users WHERE blocked_user_id = $1`
	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
