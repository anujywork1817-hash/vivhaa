package savedsearches

import (
	"context"
	"encoding/json"
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

func (r *Repository) Create(ctx context.Context, userID, name string, filters json.RawMessage, resultCount int) (SavedSearch, error) {
	const q = `
		INSERT INTO saved_searches (user_id, name, filters, result_count)
		VALUES ($1, $2, $3, $4)
		RETURNING id, user_id, name, filters, result_count, created_at`
	var s SavedSearch
	err := r.db.QueryRow(ctx, q, userID, name, filters, resultCount).Scan(
		&s.ID, &s.UserID, &s.Name, &s.Filters, &s.ResultCount, &s.CreatedAt)
	return s, err
}

func (r *Repository) CountForUser(ctx context.Context, userID string) (int, error) {
	const q = `SELECT count(*) FROM saved_searches WHERE user_id = $1`
	var count int
	err := r.db.QueryRow(ctx, q, userID).Scan(&count)
	return count, err
}

func (r *Repository) List(ctx context.Context, userID string) ([]SavedSearch, error) {
	const q = `
		SELECT id, user_id, name, filters, result_count, created_at
		FROM saved_searches WHERE user_id = $1 ORDER BY created_at DESC`
	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []SavedSearch
	for rows.Next() {
		var s SavedSearch
		if err := rows.Scan(&s.ID, &s.UserID, &s.Name, &s.Filters, &s.ResultCount, &s.CreatedAt); err != nil {
			return nil, err
		}
		results = append(results, s)
	}
	return results, rows.Err()
}

func (r *Repository) Delete(ctx context.Context, userID, id string) error {
	const q = `DELETE FROM saved_searches WHERE id = $1 AND user_id = $2`
	tag, err := r.db.Exec(ctx, q, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
