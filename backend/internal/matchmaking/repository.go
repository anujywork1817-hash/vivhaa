package matchmaking

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

// CandidatePool returns public profiles eligible for matching against the
// given user: opposite gender (when the caller's gender is known),
// excluding self, anyone already interested in, anyone blocked in either
// direction (a block must remove a member from Matches too, not just hide
// their contact details — otherwise blocking does nothing to stop them
// showing up as a suggested match), and anyone who's opted out of
// matchmaking (BUG-H07 — this flag was persisted but never filtered on).
func (r *Repository) CandidatePool(ctx context.Context, userID string, opposingGender *string, poolSize int) ([]Candidate, error) {
	q := `
		SELECT p.id, p.user_id, p.full_name, p.date_of_birth, p.gender,
		       p.religion, p.community, p.city, p.state, p.mother_tongue, p.diet, p.marital_status, p.annual_income_inr,
		       (SELECT url FROM profile_photos pp WHERE pp.profile_id = p.id ORDER BY pp.is_primary DESC, pp.sort_order ASC LIMIT 1),
		       p.height_cm, p.education, p.occupation, p.manglik
		FROM profiles p
		WHERE p.visibility = 'public'
		  AND p.user_id != $1
		  AND NOT p.matchmaking_opt_out
		  AND ($2::text IS NULL OR p.gender = $2)
		  AND NOT EXISTS (
		      -- BUG-H02: missing "deleted_at IS NULL" meant a withdrawn or
		      -- unmatched interest permanently excluded that candidate from
		      -- every future recommendation, forever — the soft-delete was
		      -- meant to let both sides start over (see migration 000016),
		      -- but this query never honored it.
		      --
		      -- Checking both directions (not just $1 as sender) is
		      -- deliberate too: someone who already sent $1 an interest
		      -- belongs in $1's Received Interests inbox to accept or
		      -- decline, not recommended again as a fresh candidate to
		      -- express interest to.
		      SELECT 1 FROM interests i
		      WHERE i.deleted_at IS NULL
		        AND ((i.sender_user_id = $1 AND i.receiver_user_id = p.user_id)
		          OR (i.sender_user_id = p.user_id AND i.receiver_user_id = $1))
		  )
		  AND NOT EXISTS (
		      SELECT 1 FROM blocked_users b
		      WHERE (b.user_id = $1 AND b.blocked_user_id = p.user_id)
		         OR (b.user_id = p.user_id AND b.blocked_user_id = $1)
		  )
		ORDER BY p.created_at DESC
		LIMIT $3`

	rows, err := r.db.Query(ctx, q, userID, opposingGender, poolSize)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var candidates []Candidate
	for rows.Next() {
		var c Candidate
		if err := rows.Scan(
			&c.ProfileID, &c.UserID, &c.FullName, &c.DateOfBirth, &c.Gender,
			&c.Religion, &c.Community, &c.City, &c.State, &c.MotherTongue, &c.Diet, &c.MaritalStatus, &c.AnnualIncomeINR,
			&c.PhotoURL, &c.HeightCM, &c.Education, &c.Occupation, &c.Manglik,
		); err != nil {
			return nil, err
		}
		candidates = append(candidates, c)
	}
	return candidates, rows.Err()
}

// NearbyCandidate is a candidate plus how far away they are.
type NearbyCandidate struct {
	Candidate
	DistanceKM float64
}

// NearbyCandidates returns public profiles that have shared a location
// (never inferred from city/IP — only ever set via UpdateLocation) within
// radiusKM of (lat, lng), nearest first. Blocked pairs are excluded in
// both directions: showing someone's live-ish location on a "near me"
// list is exactly the kind of thing a block is meant to prevent. Also
// excludes matchmaking opt-outs, same as CandidatePool (BUG-H07).
func (r *Repository) NearbyCandidates(ctx context.Context, userID string, lat, lng, radiusKM float64, opposingGender *string, limit int) ([]NearbyCandidate, error) {
	const q = `
		SELECT * FROM (
			SELECT p.id, p.user_id, p.full_name, p.date_of_birth, p.gender,
			       p.religion, p.community, p.city, p.state, p.mother_tongue, p.diet, p.marital_status, p.annual_income_inr,
			       (SELECT url FROM profile_photos pp WHERE pp.profile_id = p.id ORDER BY pp.is_primary DESC, pp.sort_order ASC LIMIT 1),
			       p.height_cm, p.education, p.occupation, p.manglik,
			       -- Haversine great-circle distance in km. No PostGIS
			       -- dependency — this is accurate enough for "how far is
			       -- this person" at matrimony-app scale (city/region), not
			       -- turn-by-turn navigation.
			       (6371 * acos(LEAST(1.0, GREATEST(-1.0,
			           cos(radians($2)) * cos(radians(p.latitude)) *
			           cos(radians(p.longitude) - radians($3)) +
			           sin(radians($2)) * sin(radians(p.latitude))
			       )))) AS distance_km
			FROM profiles p
			WHERE p.visibility = 'public'
			  AND p.user_id != $1
			  AND NOT p.matchmaking_opt_out
			  AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL
			  AND ($4::text IS NULL OR p.gender = $4)
			  AND NOT EXISTS (
			      SELECT 1 FROM blocked_users b
			      WHERE (b.user_id = $1 AND b.blocked_user_id = p.user_id)
			         OR (b.user_id = p.user_id AND b.blocked_user_id = $1)
			  )
		) nearby
		WHERE distance_km <= $5
		ORDER BY distance_km ASC
		LIMIT $6`

	rows, err := r.db.Query(ctx, q, userID, lat, lng, opposingGender, radiusKM, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []NearbyCandidate
	for rows.Next() {
		var c NearbyCandidate
		if err := rows.Scan(
			&c.ProfileID, &c.UserID, &c.FullName, &c.DateOfBirth, &c.Gender,
			&c.Religion, &c.Community, &c.City, &c.State, &c.MotherTongue, &c.Diet, &c.MaritalStatus, &c.AnnualIncomeINR,
			&c.PhotoURL, &c.HeightCM, &c.Education, &c.Occupation, &c.Manglik,
			&c.DistanceKM,
		); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}
