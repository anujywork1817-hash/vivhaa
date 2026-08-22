package visitors

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

// RecordVisit logs visitorID viewing visitedID's profile. Repeat visits
// on the same calendar day just bump visited_at rather than adding rows.
func (r *Repository) RecordVisit(ctx context.Context, visitorID, visitedID string) error {
	const q = `
		INSERT INTO profile_visits (visitor_user_id, visited_user_id)
		VALUES ($1, $2)
		ON CONFLICT (visitor_user_id, visited_user_id, visit_date)
		DO UPDATE SET visited_at = now()`
	_, err := r.db.Exec(ctx, q, visitorID, visitedID)
	return err
}

// ListVisitors returns everyone who has viewed userID's profile, most
// recent visit first, joined with a brief of each visitor's own profile.
func (r *Repository) ListVisitors(ctx context.Context, userID string, limit int) ([]VisitorEntry, error) {
	const q = `
		SELECT v.visitor_user_id, p.id, p.full_name, p.city,
		       (SELECT url FROM profile_photos pp WHERE pp.profile_id = p.id ORDER BY pp.is_primary DESC, pp.sort_order ASC LIMIT 1),
		       v.visited_at
		FROM profile_visits v
		JOIN profiles p ON p.user_id = v.visitor_user_id
		WHERE v.visited_user_id = $1
		  -- BUG-M03: unfiltered, a blocked visitor's name/photo/city and the
		  -- fact that they'd visited at all still leaked into this list —
		  -- exactly the kind of thing blocking someone is meant to prevent.
		  AND NOT EXISTS (
		      SELECT 1 FROM blocked_users b
		      WHERE (b.user_id = $1 AND b.blocked_user_id = v.visitor_user_id)
		         OR (b.user_id = v.visitor_user_id AND b.blocked_user_id = $1)
		  )
		ORDER BY v.visited_at DESC
		LIMIT $2`
	rows, err := r.db.Query(ctx, q, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var entries []VisitorEntry
	for rows.Next() {
		var e VisitorEntry
		if err := rows.Scan(&e.VisitorUserID, &e.ProfileID, &e.FullName, &e.City, &e.PhotoURL, &e.VisitedAt); err != nil {
			return nil, err
		}
		entries = append(entries, e)
	}
	return entries, rows.Err()
}
