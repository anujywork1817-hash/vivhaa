package reports

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

func (r *Repository) Create(ctx context.Context, reporterID, reportedID, reason string, details *string, category, priority string) (Report, error) {
	const q = `
		INSERT INTO reports (reporter_user_id, reported_user_id, reason, details, category, priority)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, reporter_user_id, reported_user_id, reason, details, category, priority, status, created_at`
	var rep Report
	err := r.db.QueryRow(ctx, q, reporterID, reportedID, reason, details, category, priority).Scan(
		&rep.ID, &rep.ReporterUserID, &rep.ReportedUserID, &rep.Reason, &rep.Details,
		&rep.Category, &rep.Priority, &rep.Status, &rep.CreatedAt)
	return rep, err
}
