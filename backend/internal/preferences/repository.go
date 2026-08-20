package preferences

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
	id, user_id, min_age, max_age, min_height_cm, max_height_cm,
	marital_status, religion, community, mother_tongue, education, min_income_inr,
	country, state, city, diet, profession, working_with, profile_managed_by,
	about_partner, created_at, updated_at`

func (r *Repository) scan(row pgx.Row) (Preferences, error) {
	var p Preferences
	err := row.Scan(
		&p.ID, &p.UserID, &p.MinAge, &p.MaxAge, &p.MinHeightCM, &p.MaxHeightCM,
		&p.MaritalStatus, &p.Religion, &p.Community, &p.MotherTongue, &p.Education, &p.MinIncomeINR,
		&p.Country, &p.State, &p.City, &p.Diet, &p.Profession, &p.WorkingWith, &p.ProfileManagedBy,
		&p.AboutPartner, &p.CreatedAt, &p.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return Preferences{}, ErrNotFound
	}
	return p, err
}

func (r *Repository) GetByUserID(ctx context.Context, userID string) (Preferences, error) {
	q := `SELECT ` + columns + ` FROM preferences WHERE user_id = $1`
	return r.scan(r.db.QueryRow(ctx, q, userID))
}

// Upsert creates or replaces the caller's preferences in a single call —
// there's exactly one preferences row per user.
func (r *Repository) Upsert(ctx context.Context, p Preferences) (Preferences, error) {
	q := `
		INSERT INTO preferences (
			user_id, min_age, max_age, min_height_cm, max_height_cm,
			marital_status, religion, community, mother_tongue, education, min_income_inr,
			country, state, city, diet, profession, working_with, profile_managed_by, about_partner
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
		ON CONFLICT (user_id) DO UPDATE SET
			min_age = $2, max_age = $3, min_height_cm = $4, max_height_cm = $5,
			marital_status = $6, religion = $7, community = $8, mother_tongue = $9, education = $10, min_income_inr = $11,
			country = $12, state = $13, city = $14, diet = $15, profession = $16, working_with = $17,
			profile_managed_by = $18, about_partner = $19,
			updated_at = now()
		RETURNING ` + columns

	row := r.db.QueryRow(ctx, q,
		p.UserID, p.MinAge, p.MaxAge, p.MinHeightCM, p.MaxHeightCM,
		p.MaritalStatus, p.Religion, p.Community, p.MotherTongue, p.Education, p.MinIncomeINR,
		p.Country, p.State, p.City, p.Diet, p.Profession, p.WorkingWith, p.ProfileManagedBy, p.AboutPartner,
	)
	return r.scan(row)
}
