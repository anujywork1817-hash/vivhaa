package shortlisted

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNotFound      = errors.New("not found")
	ErrAlreadyExists = errors.New("profile already shortlisted")
)

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Create(ctx context.Context, userID, targetUserID string) (Shortlisted, error) {
	const q = `
		INSERT INTO shortlisted_profiles (user_id, target_user_id)
		VALUES ($1, $2)
		RETURNING id, user_id, target_user_id, created_at`
	var s Shortlisted
	err := r.db.QueryRow(ctx, q, userID, targetUserID).Scan(&s.ID, &s.UserID, &s.TargetUserID, &s.CreatedAt)
	if isUniqueViolation(err) {
		return Shortlisted{}, ErrAlreadyExists
	}
	return s, err
}

func (r *Repository) Delete(ctx context.Context, userID, targetUserID string) error {
	const q = `DELETE FROM shortlisted_profiles WHERE user_id = $1 AND target_user_id = $2`
	tag, err := r.db.Exec(ctx, q, userID, targetUserID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// List excludes any target that's blocked in either direction — see
// favourites.Repository.List for why this filters rather than deletes.
func (r *Repository) List(ctx context.Context, userID string) ([]ShortlistedWithProfile, error) {
	const q = `
		SELECT s.id, s.user_id, s.target_user_id, s.created_at,
		       p.id, p.full_name, p.city,
		       (SELECT url FROM profile_photos pp WHERE pp.profile_id = p.id ORDER BY pp.is_primary DESC, pp.sort_order ASC LIMIT 1),
		       p.date_of_birth, p.height_cm, p.marital_status, p.religion, p.education, p.occupation, p.diet, p.manglik
		FROM shortlisted_profiles s
		JOIN profiles p ON p.user_id = s.target_user_id
		WHERE s.user_id = $1
		  AND NOT EXISTS (
		      SELECT 1 FROM blocked_users b
		      WHERE (b.user_id = $1 AND b.blocked_user_id = s.target_user_id)
		         OR (b.user_id = s.target_user_id AND b.blocked_user_id = $1)
		  )
		ORDER BY s.created_at DESC`
	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []ShortlistedWithProfile
	for rows.Next() {
		var swp ShortlistedWithProfile
		if err := rows.Scan(
			&swp.ID, &swp.UserID, &swp.TargetUserID, &swp.CreatedAt,
			&swp.ProfileID, &swp.FullName, &swp.City, &swp.PhotoURL,
			&swp.DateOfBirth, &swp.HeightCM, &swp.MaritalStatus, &swp.Religion, &swp.Education, &swp.Occupation, &swp.Diet, &swp.Manglik,
		); err != nil {
			return nil, err
		}
		results = append(results, swp)
	}
	return results, rows.Err()
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
