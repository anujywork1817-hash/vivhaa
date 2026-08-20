package favourites

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNotFound      = errors.New("not found")
	ErrAlreadyExists = errors.New("profile already in favourites")
)

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Create(ctx context.Context, userID, targetUserID string) (Favourite, error) {
	const q = `
		INSERT INTO favourites (user_id, target_user_id)
		VALUES ($1, $2)
		RETURNING id, user_id, target_user_id, created_at`
	var f Favourite
	err := r.db.QueryRow(ctx, q, userID, targetUserID).Scan(&f.ID, &f.UserID, &f.TargetUserID, &f.CreatedAt)
	if isUniqueViolation(err) {
		return Favourite{}, ErrAlreadyExists
	}
	return f, err
}

func (r *Repository) Delete(ctx context.Context, userID, targetUserID string) error {
	const q = `DELETE FROM favourites WHERE user_id = $1 AND target_user_id = $2`
	tag, err := r.db.Exec(ctx, q, userID, targetUserID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// List excludes any target that's blocked in either direction — a block
// must freeze the favourite out of the active list too, not just future
// adds, without deleting the underlying row (an unblock brings it right
// back).
func (r *Repository) List(ctx context.Context, userID string) ([]FavouriteWithProfile, error) {
	const q = `
		SELECT f.id, f.user_id, f.target_user_id, f.created_at,
		       p.id, p.full_name, p.city,
		       (SELECT url FROM profile_photos pp WHERE pp.profile_id = p.id ORDER BY pp.is_primary DESC, pp.sort_order ASC LIMIT 1),
		       p.date_of_birth, p.height_cm, p.marital_status, p.religion, p.education, p.occupation, p.diet, p.manglik
		FROM favourites f
		JOIN profiles p ON p.user_id = f.target_user_id
		WHERE f.user_id = $1
		  AND NOT EXISTS (
		      SELECT 1 FROM blocked_users b
		      WHERE (b.user_id = $1 AND b.blocked_user_id = f.target_user_id)
		         OR (b.user_id = f.target_user_id AND b.blocked_user_id = $1)
		  )
		ORDER BY f.created_at DESC`
	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []FavouriteWithProfile
	for rows.Next() {
		var fwp FavouriteWithProfile
		if err := rows.Scan(
			&fwp.ID, &fwp.UserID, &fwp.TargetUserID, &fwp.CreatedAt,
			&fwp.ProfileID, &fwp.FullName, &fwp.City, &fwp.PhotoURL,
			&fwp.DateOfBirth, &fwp.HeightCM, &fwp.MaritalStatus, &fwp.Religion, &fwp.Education, &fwp.Occupation, &fwp.Diet, &fwp.Manglik,
		); err != nil {
			return nil, err
		}
		results = append(results, fwp)
	}
	return results, rows.Err()
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
