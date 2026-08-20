package moderation

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

const columns = `id, reporter_user_id, reported_user_id, reason, details, status, reviewed_by, review_notes, created_at, reviewed_at`

func (r *Repository) scan(row pgx.Row) (Report, error) {
	var rep Report
	err := row.Scan(&rep.ID, &rep.ReporterUserID, &rep.ReportedUserID, &rep.Reason, &rep.Details, &rep.Status, &rep.ReviewedBy, &rep.ReviewNotes, &rep.CreatedAt, &rep.ReviewedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Report{}, ErrNotFound
	}
	return rep, err
}

func (r *Repository) ListByStatus(ctx context.Context, status string, limit, offset int) ([]Report, error) {
	q := `SELECT ` + columns + ` FROM reports WHERE status = $1 ORDER BY created_at ASC LIMIT $2 OFFSET $3`
	rows, err := r.db.Query(ctx, q, status, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []Report
	for rows.Next() {
		rep, err := r.scan(rows)
		if err != nil {
			return nil, err
		}
		results = append(results, rep)
	}
	return results, rows.Err()
}

func (r *Repository) CountByStatus(ctx context.Context, status string) (int, error) {
	var total int
	err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM reports WHERE status = $1`, status).Scan(&total)
	return total, err
}

func (r *Repository) GetByID(ctx context.Context, id string) (Report, error) {
	q := `SELECT ` + columns + ` FROM reports WHERE id = $1`
	return r.scan(r.db.QueryRow(ctx, q, id))
}

func (r *Repository) Resolve(ctx context.Context, id, status, reviewerID string, notes *string) (Report, error) {
	q := `
		UPDATE reports SET status = $2, reviewed_by = $3, review_notes = $4, reviewed_at = now()
		WHERE id = $1
		RETURNING ` + columns
	return r.scan(r.db.QueryRow(ctx, q, id, status, reviewerID, notes))
}

func (r *Repository) SuspendUser(ctx context.Context, userID string) error {
	const q = `UPDATE users SET status = 'suspended', updated_at = now() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, userID)
	return err
}
