package notifications

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("not found")

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Create(ctx context.Context, userID, notifType, title string, body *string, data []byte) (Notification, error) {
	const q = `
		INSERT INTO notifications (user_id, type, title, body, data)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, user_id, type, title, body, data, read_at, created_at`
	var n Notification
	err := r.db.QueryRow(ctx, q, userID, notifType, title, body, data).Scan(
		&n.ID, &n.UserID, &n.Type, &n.Title, &n.Body, &n.Data, &n.ReadAt, &n.CreatedAt)
	return n, err
}

func (r *Repository) List(ctx context.Context, userID string, limit, offset int) ([]Notification, error) {
	const q = `
		SELECT id, user_id, type, title, body, data, read_at, created_at
		FROM notifications WHERE user_id = $1
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3`
	rows, err := r.db.Query(ctx, q, userID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []Notification
	for rows.Next() {
		var n Notification
		if err := rows.Scan(&n.ID, &n.UserID, &n.Type, &n.Title, &n.Body, &n.Data, &n.ReadAt, &n.CreatedAt); err != nil {
			return nil, err
		}
		results = append(results, n)
	}
	return results, rows.Err()
}

func (r *Repository) CountUnread(ctx context.Context, userID string) (int, error) {
	const q = `SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND read_at IS NULL`
	var count int
	err := r.db.QueryRow(ctx, q, userID).Scan(&count)
	return count, err
}

func (r *Repository) MarkRead(ctx context.Context, userID, id string) error {
	const q = `UPDATE notifications SET read_at = now() WHERE id = $1 AND user_id = $2 AND read_at IS NULL`
	tag, err := r.db.Exec(ctx, q, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) MarkAllRead(ctx context.Context, userID string) error {
	const q = `UPDATE notifications SET read_at = now() WHERE user_id = $1 AND read_at IS NULL`
	_, err := r.db.Exec(ctx, q, userID)
	return err
}
