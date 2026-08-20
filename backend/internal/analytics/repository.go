package analytics

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Create(ctx context.Context, eventType string, userID *string, metadata []byte) error {
	const q = `INSERT INTO analytics_events (event_type, user_id, metadata) VALUES ($1, $2, $3)`
	_, err := r.db.Exec(ctx, q, eventType, userID, metadata)
	return err
}

func (r *Repository) CountByTypeSince(ctx context.Context, eventType string, since time.Time) (int, error) {
	const q = `SELECT COUNT(*) FROM analytics_events WHERE event_type = $1 AND created_at >= $2`
	var count int
	err := r.db.QueryRow(ctx, q, eventType, since).Scan(&count)
	return count, err
}

func (r *Repository) CountByType(ctx context.Context, eventType string) (int, error) {
	const q = `SELECT COUNT(*) FROM analytics_events WHERE event_type = $1`
	var count int
	err := r.db.QueryRow(ctx, q, eventType).Scan(&count)
	return count, err
}

func (r *Repository) ListRecent(ctx context.Context, limit int) ([]Event, error) {
	const q = `SELECT id, event_type, user_id, metadata, created_at FROM analytics_events ORDER BY created_at DESC LIMIT $1`
	rows, err := r.db.Query(ctx, q, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []Event
	for rows.Next() {
		var e Event
		if err := rows.Scan(&e.ID, &e.EventType, &e.UserID, &e.Metadata, &e.CreatedAt); err != nil {
			return nil, err
		}
		events = append(events, e)
	}
	return events, rows.Err()
}
