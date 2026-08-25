package verification

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

const columns = `id, user_id, document_type, document_key, document_url, status, reviewed_by, review_notes, created_at, reviewed_at`

func (r *Repository) scan(row pgx.Row) (Verification, error) {
	var v Verification
	err := row.Scan(&v.ID, &v.UserID, &v.DocumentType, &v.DocumentKey, &v.DocumentURL, &v.Status, &v.ReviewedBy, &v.ReviewNotes, &v.CreatedAt, &v.ReviewedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Verification{}, ErrNotFound
	}
	return v, err
}

// Create inserts a new verification request. document_url is intentionally
// left NULL — the document lives in a private bucket now, so there is no
// stored URL; a viewable link is minted on demand (see Service.toResponse).
func (r *Repository) Create(ctx context.Context, userID, documentType, documentKey string) (Verification, error) {
	q := `
		INSERT INTO verifications (user_id, document_type, document_key)
		VALUES ($1, $2, $3)
		RETURNING ` + columns
	return r.scan(r.db.QueryRow(ctx, q, userID, documentType, documentKey))
}

func (r *Repository) GetLatestByUserID(ctx context.Context, userID string) (Verification, error) {
	q := `SELECT ` + columns + ` FROM verifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 1`
	return r.scan(r.db.QueryRow(ctx, q, userID))
}

// GetLatestByUserIDAndType scopes the "already pending/approved" check to
// a single document type, so e.g. a pending personal_document submission
// doesn't block a separate selfie submission (and vice versa).
func (r *Repository) GetLatestByUserIDAndType(ctx context.Context, userID, documentType string) (Verification, error) {
	q := `SELECT ` + columns + ` FROM verifications WHERE user_id = $1 AND document_type = $2 ORDER BY created_at DESC LIMIT 1`
	return r.scan(r.db.QueryRow(ctx, q, userID, documentType))
}

// ListByUserID returns every document a user has ever submitted, newest
// first — used both for the user's own "my documents" view and, with an
// arbitrary userID, for the admin per-customer documents view.
func (r *Repository) ListByUserID(ctx context.Context, userID string) ([]Verification, error) {
	q := `SELECT ` + columns + ` FROM verifications WHERE user_id = $1 ORDER BY created_at DESC`
	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []Verification
	for rows.Next() {
		v, err := r.scan(rows)
		if err != nil {
			return nil, err
		}
		results = append(results, v)
	}
	return results, rows.Err()
}

func (r *Repository) GetByID(ctx context.Context, id string) (Verification, error) {
	q := `SELECT ` + columns + ` FROM verifications WHERE id = $1`
	return r.scan(r.db.QueryRow(ctx, q, id))
}

func (r *Repository) ListByStatus(ctx context.Context, status string, limit, offset int) ([]Verification, error) {
	q := `SELECT ` + columns + ` FROM verifications WHERE status = $1 ORDER BY created_at ASC LIMIT $2 OFFSET $3`
	rows, err := r.db.Query(ctx, q, status, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []Verification
	for rows.Next() {
		v, err := r.scan(rows)
		if err != nil {
			return nil, err
		}
		results = append(results, v)
	}
	return results, rows.Err()
}

func (r *Repository) CountByStatus(ctx context.Context, status string) (int, error) {
	var total int
	err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM verifications WHERE status = $1`, status).Scan(&total)
	return total, err
}

// HasApproved reports whether userID has at least one currently-approved
// verification of any document type — used to recompute the profile
// verified badge after a review, rather than assuming this one action
// alone determines it (a user can hold more than one approved document).
func (r *Repository) HasApproved(ctx context.Context, userID string) (bool, error) {
	var exists bool
	err := r.db.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM verifications WHERE user_id = $1 AND status = 'approved')`,
		userID).Scan(&exists)
	return exists, err
}

// Review transitions id from 'pending' to status (approved/rejected) —
// gated on the row's *current* status being 'pending' in the WHERE
// clause itself (an atomic conditional UPDATE, not a separate read-then-
// write), so two admins hitting approve/reject on the same submission at
// the same time, or a re-approve/re-reject of an already-decided one,
// can't silently overwrite review history: only the first one to land
// actually transitions the row, and every other caller gets ErrNotFound
// (no row matched) back from the scan below.
func (r *Repository) Review(ctx context.Context, id, status, reviewerID string, notes *string) (Verification, error) {
	q := `
		UPDATE verifications SET status = $2, reviewed_by = $3, review_notes = $4, reviewed_at = now()
		WHERE id = $1 AND status = 'pending'
		RETURNING ` + columns
	return r.scan(r.db.QueryRow(ctx, q, id, status, reviewerID, notes))
}
