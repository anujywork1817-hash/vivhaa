package ai

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

const historyLimit = 100

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Append(ctx context.Context, userID, role, content string) (Message, error) {
	const q = `
		INSERT INTO ai_messages (user_id, role, content)
		VALUES ($1, $2, $3)
		RETURNING id, user_id, role, content, created_at`
	var m Message
	err := r.db.QueryRow(ctx, q, userID, role, content).Scan(&m.ID, &m.UserID, &m.Role, &m.Content, &m.CreatedAt)
	return m, err
}

// History returns the user's most recent messages, oldest first — ready
// to feed straight into the model as conversation context.
func (r *Repository) History(ctx context.Context, userID string) ([]Message, error) {
	const q = `
		SELECT id, user_id, role, content, created_at FROM (
			SELECT id, user_id, role, content, created_at
			FROM ai_messages WHERE user_id = $1
			ORDER BY created_at DESC LIMIT $2
		) recent ORDER BY created_at ASC`
	rows, err := r.db.Query(ctx, q, userID, historyLimit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []Message
	for rows.Next() {
		var m Message
		if err := rows.Scan(&m.ID, &m.UserID, &m.Role, &m.Content, &m.CreatedAt); err != nil {
			return nil, err
		}
		messages = append(messages, m)
	}
	return messages, rows.Err()
}
