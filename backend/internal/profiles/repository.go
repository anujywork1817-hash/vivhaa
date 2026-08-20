package profiles

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

const profileColumns = `
	id, user_id, full_name, date_of_birth, gender, height_cm, marital_status,
	religion, community, mother_tongue, education, occupation, annual_income_inr,
	country, state, city, family_type, family_status, father_occupation, mother_occupation,
	siblings_count, diet, smoking, drinking, about_me,
	profile_for, sub_community, caste_no_bar, college, work_with, company_name, matchmaking_opt_out,
	family_values, lives_with_family, hobbies, selfie_verified, manglik, rashi, nakshatra,
	birth_time, birth_place, weight_kg, body_type, complexion, has_disability,
	visibility, profile_code, created_at, updated_at, latitude, longitude`

func (r *Repository) scanProfile(row pgx.Row) (Profile, error) {
	var p Profile
	err := row.Scan(
		&p.ID, &p.UserID, &p.FullName, &p.DateOfBirth, &p.Gender, &p.HeightCM, &p.MaritalStatus,
		&p.Religion, &p.Community, &p.MotherTongue, &p.Education, &p.Occupation, &p.AnnualIncomeINR,
		&p.Country, &p.State, &p.City, &p.FamilyType, &p.FamilyStatus, &p.FatherOccupation, &p.MotherOccupation,
		&p.SiblingsCount, &p.Diet, &p.Smoking, &p.Drinking, &p.AboutMe,
		&p.ProfileFor, &p.SubCommunity, &p.CasteNoBar, &p.College, &p.WorkWith, &p.CompanyName, &p.MatchmakingOptOut,
		&p.FamilyValues, &p.LivesWithFamily, &p.Hobbies, &p.SelfieVerified, &p.Manglik, &p.Rashi, &p.Nakshatra,
		&p.BirthTime, &p.BirthPlace, &p.WeightKG, &p.BodyType, &p.Complexion, &p.HasDisability,
		&p.Visibility, &p.ProfileCode, &p.CreatedAt, &p.UpdatedAt, &p.Latitude, &p.Longitude,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return Profile{}, ErrNotFound
	}
	return p, err
}

func (r *Repository) Create(ctx context.Context, userID string, p Profile) (Profile, error) {
	q := `
		INSERT INTO profiles (
			user_id, full_name, date_of_birth, gender, height_cm, marital_status,
			religion, community, mother_tongue, education, occupation, annual_income_inr,
			country, state, city, family_type, family_status, father_occupation, mother_occupation,
			siblings_count, diet, smoking, drinking, about_me,
			profile_for, sub_community, caste_no_bar, college, work_with, company_name, matchmaking_opt_out,
			family_values, lives_with_family, hobbies, selfie_verified, manglik, rashi, nakshatra,
			birth_time, birth_place, weight_kg, body_type, complexion, has_disability
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
			$21, $22, $23, $24, $25, $26, $27, $28, $29, $30, $31, $32, $33, $34, $35, $36, $37, $38,
			$39, $40, $41, $42, $43, $44
		)
		RETURNING ` + profileColumns

	row := r.db.QueryRow(ctx, q,
		userID, p.FullName, p.DateOfBirth, p.Gender, p.HeightCM, p.MaritalStatus,
		p.Religion, p.Community, p.MotherTongue, p.Education, p.Occupation, p.AnnualIncomeINR,
		p.Country, p.State, p.City, p.FamilyType, p.FamilyStatus, p.FatherOccupation, p.MotherOccupation,
		p.SiblingsCount, p.Diet, p.Smoking, p.Drinking, p.AboutMe,
		p.ProfileFor, p.SubCommunity, p.CasteNoBar, p.College, p.WorkWith, p.CompanyName, p.MatchmakingOptOut,
		p.FamilyValues, p.LivesWithFamily, p.Hobbies, p.SelfieVerified, p.Manglik, p.Rashi, p.Nakshatra,
		p.BirthTime, p.BirthPlace, p.WeightKG, p.BodyType, p.Complexion, p.HasDisability,
	)
	return r.scanProfile(row)
}

func (r *Repository) GetByUserID(ctx context.Context, userID string) (Profile, error) {
	q := `SELECT ` + profileColumns + ` FROM profiles WHERE user_id = $1`
	return r.scanProfile(r.db.QueryRow(ctx, q, userID))
}

func (r *Repository) GetByID(ctx context.Context, id string) (Profile, error) {
	q := `SELECT ` + profileColumns + ` FROM profiles WHERE id = $1`
	return r.scanProfile(r.db.QueryRow(ctx, q, id))
}

// GetByCode looks up a profile by its short, user-facing profile code
// (e.g. "VV100042") rather than its UUID — case-insensitive since users
// may type it in lowercase.
func (r *Repository) GetByCode(ctx context.Context, code string) (Profile, error) {
	q := `SELECT ` + profileColumns + ` FROM profiles WHERE upper(profile_code) = upper($1)`
	return r.scanProfile(r.db.QueryRow(ctx, q, code))
}

// ListPublicUserIDs returns the user_id of every public profile — the
// set cmd/scheduler warms the daily-matches cache for.
func (r *Repository) ListPublicUserIDs(ctx context.Context) ([]string, error) {
	rows, err := r.db.Query(ctx, `SELECT user_id FROM profiles WHERE visibility = 'public'`)
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

func (r *Repository) Update(ctx context.Context, p Profile) (Profile, error) {
	q := `
		UPDATE profiles SET
			full_name = $2, date_of_birth = $3, gender = $4, height_cm = $5, marital_status = $6,
			religion = $7, community = $8, mother_tongue = $9, education = $10, occupation = $11, annual_income_inr = $12,
			country = $13, state = $14, city = $15, family_type = $16, family_status = $17, father_occupation = $18, mother_occupation = $19,
			siblings_count = $20, diet = $21, smoking = $22, drinking = $23, about_me = $24,
			profile_for = $25, sub_community = $26, caste_no_bar = $27, college = $28, work_with = $29, company_name = $30, matchmaking_opt_out = $31,
			family_values = $32, lives_with_family = $33, hobbies = $34, selfie_verified = $35, manglik = $36, rashi = $37, nakshatra = $38,
			birth_time = $39, birth_place = $40, weight_kg = $41, body_type = $42, complexion = $43, has_disability = $44,
			visibility = $45,
			updated_at = now()
		WHERE id = $1
		RETURNING ` + profileColumns

	row := r.db.QueryRow(ctx, q,
		p.ID, p.FullName, p.DateOfBirth, p.Gender, p.HeightCM, p.MaritalStatus,
		p.Religion, p.Community, p.MotherTongue, p.Education, p.Occupation, p.AnnualIncomeINR,
		p.Country, p.State, p.City, p.FamilyType, p.FamilyStatus, p.FatherOccupation, p.MotherOccupation,
		p.SiblingsCount, p.Diet, p.Smoking, p.Drinking, p.AboutMe,
		p.ProfileFor, p.SubCommunity, p.CasteNoBar, p.College, p.WorkWith, p.CompanyName, p.MatchmakingOptOut,
		p.FamilyValues, p.LivesWithFamily, p.Hobbies, p.SelfieVerified, p.Manglik, p.Rashi, p.Nakshatra,
		p.BirthTime, p.BirthPlace, p.WeightKG, p.BodyType, p.Complexion, p.HasDisability,
		p.Visibility,
	)
	return r.scanProfile(row)
}

// UpdateLocation records the caller's current GPS coordinates, powering
// the "Near Me" feature. Only ever called from an explicit share action —
// never inferred — so a profile with null lat/lng simply means that
// member has never opted in.
func (r *Repository) UpdateLocation(ctx context.Context, userID string, lat, lng float64) error {
	const q = `UPDATE profiles SET latitude = $2, longitude = $3, location_updated_at = now()
	           WHERE user_id = $1`
	tag, err := r.db.Exec(ctx, q, userID, lat, lng)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// SetSelfieVerified flips the verified badge — the only place this ever
// happens is admin verification review (see BUG-C05: it must never be
// user-settable via ProfileInput).
func (r *Repository) SetSelfieVerified(ctx context.Context, userID string, verified bool) error {
	const q = `UPDATE profiles SET selfie_verified = $2 WHERE user_id = $1`
	tag, err := r.db.Exec(ctx, q, userID, verified)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) CreatePhoto(ctx context.Context, profileID, objectKey, url string, isPrimary bool) (Photo, error) {
	const q = `
		INSERT INTO profile_photos (profile_id, object_key, url, is_primary)
		VALUES ($1, $2, $3, $4)
		RETURNING id, profile_id, object_key, url, is_primary, sort_order, created_at`
	var ph Photo
	err := r.db.QueryRow(ctx, q, profileID, objectKey, url, isPrimary).Scan(
		&ph.ID, &ph.ProfileID, &ph.ObjectKey, &ph.URL, &ph.IsPrimary, &ph.SortOrder, &ph.CreatedAt)
	return ph, err
}

// SetPrimaryPhoto makes photoID the profile's primary photo, clearing the
// flag on every other photo of that profile. Both writes run in one
// transaction so a profile can never be left with two primaries (or none)
// — the "primary" is what clients show as the profile picture, so an
// ambiguous state means the wrong photo gets displayed.
func (r *Repository) SetPrimaryPhoto(ctx context.Context, profileID, photoID string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx,
		`UPDATE profile_photos SET is_primary = FALSE WHERE profile_id = $1`, profileID); err != nil {
		return err
	}

	tag, err := tx.Exec(ctx,
		`UPDATE profile_photos SET is_primary = TRUE WHERE id = $1 AND profile_id = $2`, photoID, profileID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}

	return tx.Commit(ctx)
}

func (r *Repository) ListPhotos(ctx context.Context, profileID string) ([]Photo, error) {
	const q = `
		SELECT id, profile_id, object_key, url, is_primary, sort_order, created_at
		FROM profile_photos WHERE profile_id = $1 ORDER BY is_primary DESC, sort_order ASC, created_at ASC`
	rows, err := r.db.Query(ctx, q, profileID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var photos []Photo
	for rows.Next() {
		var ph Photo
		if err := rows.Scan(&ph.ID, &ph.ProfileID, &ph.ObjectKey, &ph.URL, &ph.IsPrimary, &ph.SortOrder, &ph.CreatedAt); err != nil {
			return nil, err
		}
		photos = append(photos, ph)
	}
	return photos, rows.Err()
}

func (r *Repository) CountPhotos(ctx context.Context, profileID string) (int, error) {
	const q = `SELECT COUNT(*) FROM profile_photos WHERE profile_id = $1`
	var count int
	err := r.db.QueryRow(ctx, q, profileID).Scan(&count)
	return count, err
}

func (r *Repository) GetPhoto(ctx context.Context, photoID string) (Photo, error) {
	const q = `SELECT id, profile_id, object_key, url, is_primary, sort_order, created_at FROM profile_photos WHERE id = $1`
	var ph Photo
	err := r.db.QueryRow(ctx, q, photoID).Scan(&ph.ID, &ph.ProfileID, &ph.ObjectKey, &ph.URL, &ph.IsPrimary, &ph.SortOrder, &ph.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Photo{}, ErrNotFound
	}
	return ph, err
}

func (r *Repository) DeletePhoto(ctx context.Context, photoID string) error {
	const q = `DELETE FROM profile_photos WHERE id = $1`
	_, err := r.db.Exec(ctx, q, photoID)
	return err
}
