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

const columns = `r.id, r.reporter_user_id, r.reported_user_id, r.reason, r.details, r.category, r.priority,
	r.status, r.reviewed_by, r.review_notes, r.created_at, r.reviewed_at,
	rptr.full_name, rptd.full_name`

const joins = `
	FROM reports r
	LEFT JOIN profiles rptr ON rptr.user_id = r.reporter_user_id
	LEFT JOIN profiles rptd ON rptd.user_id = r.reported_user_id`

func (r *Repository) scan(row pgx.Row) (Report, error) {
	var rep Report
	err := row.Scan(&rep.ID, &rep.ReporterUserID, &rep.ReportedUserID, &rep.Reason, &rep.Details,
		&rep.Category, &rep.Priority, &rep.Status, &rep.ReviewedBy, &rep.ReviewNotes, &rep.CreatedAt, &rep.ReviewedAt,
		&rep.ReporterName, &rep.ReportedName)
	if errors.Is(err, pgx.ErrNoRows) {
		return Report{}, ErrNotFound
	}
	return rep, err
}

// ListByStatus orders high-priority (safety/money) reports first, then
// oldest-first within each priority tier — a "financial fraud" report
// filed a minute ago shouldn't sit behind a week of routine spam reports
// just because it's newer.
func (r *Repository) ListByStatus(ctx context.Context, status string, limit, offset int) ([]Report, error) {
	q := `SELECT ` + columns + joins + `
		WHERE r.status = $1
		ORDER BY CASE r.priority WHEN 'high' THEN 0 ELSE 1 END, r.created_at ASC
		LIMIT $2 OFFSET $3`
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
	q := `SELECT ` + columns + joins + ` WHERE r.id = $1`
	return r.scan(r.db.QueryRow(ctx, q, id))
}

func (r *Repository) Resolve(ctx context.Context, id, status, reviewerID string, notes *string) (Report, error) {
	q := `
		WITH updated AS (
			UPDATE reports SET status = $2, reviewed_by = $3, review_notes = $4, reviewed_at = now()
			WHERE id = $1
			RETURNING *
		)
		SELECT ` + columns + `
		FROM updated r
		LEFT JOIN profiles rptr ON rptr.user_id = r.reporter_user_id
		LEFT JOIN profiles rptd ON rptd.user_id = r.reported_user_id`
	return r.scan(r.db.QueryRow(ctx, q, id, status, reviewerID, notes))
}

func (r *Repository) SuspendUser(ctx context.Context, userID string) error {
	const q = `UPDATE users SET status = 'suspended', updated_at = now() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, userID)
	return err
}
