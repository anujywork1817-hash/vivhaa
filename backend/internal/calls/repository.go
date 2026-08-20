package calls

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNotFound = errors.New("not found")
	// ErrBusy means one of the two participants already has another
	// active call — surfaced by Create, backed by active_calls_by_user's
	// user_id primary key (see that table's migration comment). This is
	// the cross-instance replacement for the old in-memory userToCall
	// map's busy check (BUG-C08): the DB constraint is what actually
	// enforces "one active call per user" now, not a local mutex+map that
	// only knew about calls this one process had seen.
	ErrBusy = errors.New("user already has an active call")
)

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

const sessionColumns = `id, caller_user_id, callee_user_id, status, is_video, started_at, connected_at, ended_at, duration_seconds, end_reason`

func scanSession(row pgx.Row) (CallSession, error) {
	var cs CallSession
	err := row.Scan(&cs.ID, &cs.CallerUserID, &cs.CalleeUserID, &cs.Status, &cs.IsVideo, &cs.StartedAt,
		&cs.ConnectedAt, &cs.EndedAt, &cs.DurationSeconds, &cs.EndReason)
	if errors.Is(err, pgx.ErrNoRows) {
		return CallSession{}, ErrNotFound
	}
	return cs, err
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// Create persists a call session with a caller-supplied ID — the same ID
// already in use as the WebRTC signaling correlation ID (see
// Service.initiate) — and, in the same transaction, claims both
// participants in active_calls_by_user. That claim is what makes "one
// active call per user" hold across instances: if either participant is
// already claimed by another row, the unique violation on user_id rolls
// the whole transaction back and this returns ErrBusy instead of leaving
// a call_sessions row with no matching claim.
func (r *Repository) Create(ctx context.Context, id, callerUserID, calleeUserID string, isVideo bool) (CallSession, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return CallSession{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	const insertSession = `
		INSERT INTO call_sessions (id, caller_user_id, callee_user_id, status, is_video)
		VALUES ($1, $2, $3, 'initiated', $4)
		RETURNING ` + sessionColumns
	cs, err := scanSession(tx.QueryRow(ctx, insertSession, id, callerUserID, calleeUserID, isVideo))
	if err != nil {
		return CallSession{}, err
	}

	const claim = `INSERT INTO active_calls_by_user (user_id, call_id) VALUES ($1, $3), ($2, $3)`
	if _, err := tx.Exec(ctx, claim, callerUserID, calleeUserID, id); err != nil {
		if isUniqueViolation(err) {
			return CallSession{}, ErrBusy
		}
		return CallSession{}, err
	}

	if err := tx.Commit(ctx); err != nil {
		return CallSession{}, err
	}
	return cs, nil
}

func (r *Repository) GetByID(ctx context.Context, id string) (CallSession, error) {
	const q = `SELECT ` + sessionColumns + ` FROM call_sessions WHERE id = $1`
	return scanSession(r.db.QueryRow(ctx, q, id))
}

// GetActiveForUser finds the one call userID is currently claimed in, if
// any — the cross-instance replacement for the old in-memory userToCall
// map's lookup by user, used by Service.HandleDisconnect (a dropped
// connection carries no call ID with it, only a user ID).
func (r *Repository) GetActiveForUser(ctx context.Context, userID string) (CallSession, error) {
	const q = `
		SELECT cs.id, cs.caller_user_id, cs.callee_user_id, cs.status, cs.is_video,
		       cs.started_at, cs.connected_at, cs.ended_at, cs.duration_seconds, cs.end_reason
		FROM call_sessions cs
		JOIN active_calls_by_user a ON a.call_id = cs.id
		WHERE a.user_id = $1`
	return scanSession(r.db.QueryRow(ctx, q, userID))
}

func (r *Repository) MarkOngoing(ctx context.Context, id string) error {
	const q = `UPDATE call_sessions SET status = 'ongoing', connected_at = now() WHERE id = $1 AND connected_at IS NULL`
	_, err := r.db.Exec(ctx, q, id)
	return err
}

// End finalizes a session and releases both participants' claim in
// active_calls_by_user — the same table Create used to atomically claim
// them, so ending a call is what frees a user to start or receive a new
// one. duration_seconds is only ever computed from connected_at (not
// started_at) — time spent ringing before an answer isn't call duration,
// so a call that never connected gets no duration at all rather than a
// misleading one measured from when it started ringing.
func (r *Repository) End(ctx context.Context, id, status, endReason string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	const q = `
		UPDATE call_sessions
		SET status = $2,
		    end_reason = $3,
		    ended_at = now(),
		    duration_seconds = CASE
		        WHEN connected_at IS NOT NULL THEN EXTRACT(EPOCH FROM (now() - connected_at))::int
		        ELSE NULL
		    END
		WHERE id = $1 AND ended_at IS NULL`
	tag, err := tx.Exec(ctx, q, id, status, endReason)
	if err != nil {
		return err
	}
	// Already ended by someone else (a race between two end paths, e.g.
	// the sweep and an explicit call:end landing at nearly the same
	// moment) — nothing changed, so nothing to release either; whichever
	// path ended it first already did.
	if tag.RowsAffected() == 0 {
		return tx.Commit(ctx)
	}

	if _, err := tx.Exec(ctx, `DELETE FROM active_calls_by_user WHERE call_id = $1`, id); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// SweepExpiredRinging atomically transitions every call still 'initiated'
// past olderThan to 'missed' and releases both participants' claims — the
// cross-instance replacement for the old per-call *time.Timer, which only
// ever existed in the one process that created it and vanished (leaving a
// zombie call) if that instance restarted. UPDATE...RETURNING makes each
// row's transition atomic: if more than one instance's sweep runs at the
// same moment, a given row is only ever returned to exactly one of them,
// so a call is never timed out (or its events pushed) twice.
func (r *Repository) SweepExpiredRinging(ctx context.Context, olderThan time.Duration) ([]CallSession, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	const q = `
		UPDATE call_sessions
		SET status = 'missed', end_reason = 'timeout', ended_at = now()
		WHERE status = 'initiated' AND started_at < now() - make_interval(secs => $1)
		RETURNING ` + sessionColumns
	rows, err := tx.Query(ctx, q, olderThan.Seconds())
	if err != nil {
		return nil, err
	}
	var swept []CallSession
	for rows.Next() {
		cs, err := scanSession(rows)
		if err != nil {
			rows.Close()
			return nil, err
		}
		swept = append(swept, cs)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	if len(swept) > 0 {
		ids := make([]string, len(swept))
		for i, cs := range swept {
			ids[i] = cs.ID
		}
		if _, err := tx.Exec(ctx, `DELETE FROM active_calls_by_user WHERE call_id = ANY($1)`, ids); err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return swept, nil
}

type ListFilter struct {
	Status   *string
	FromDate *time.Time
	ToDate   *time.Time
	Page     int
	Limit    int
}

// ListForAdmin backs GET /admin/call-history — every call session,
// newest first, joined against both participants' profile for display,
// filterable by status and a started_at date range.
func (r *Repository) ListForAdmin(ctx context.Context, f ListFilter) ([]CallSessionWithProfiles, int, error) {
	where := []string{"1=1"}
	args := []interface{}{}

	add := func(cond string, val interface{}) {
		args = append(args, val)
		where = append(where, fmt.Sprintf(cond, len(args)))
	}
	if f.Status != nil {
		add("cs.status = $%d", *f.Status)
	}
	if f.FromDate != nil {
		add("cs.started_at >= $%d", *f.FromDate)
	}
	if f.ToDate != nil {
		add("cs.started_at <= $%d", *f.ToDate)
	}
	whereClause := strings.Join(where, " AND ")

	var total int
	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM call_sessions cs WHERE `+whereClause, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	args = append(args, f.Limit, (f.Page-1)*f.Limit)
	q := fmt.Sprintf(`
		SELECT cs.id, cs.caller_user_id, cs.callee_user_id, cs.status, cs.is_video, cs.started_at, cs.connected_at,
		       cs.ended_at, cs.duration_seconds, cs.end_reason, pc.full_name, pe.full_name
		FROM call_sessions cs
		LEFT JOIN profiles pc ON pc.user_id = cs.caller_user_id
		LEFT JOIN profiles pe ON pe.user_id = cs.callee_user_id
		WHERE %s
		ORDER BY cs.started_at DESC
		LIMIT $%d OFFSET $%d`, whereClause, len(args)-1, len(args))

	rows, err := r.db.Query(ctx, q, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var out []CallSessionWithProfiles
	for rows.Next() {
		var cs CallSessionWithProfiles
		if err := rows.Scan(
			&cs.ID, &cs.CallerUserID, &cs.CalleeUserID, &cs.Status, &cs.IsVideo, &cs.StartedAt, &cs.ConnectedAt,
			&cs.EndedAt, &cs.DurationSeconds, &cs.EndReason, &cs.CallerName, &cs.CalleeName,
		); err != nil {
			return nil, 0, err
		}
		out = append(out, cs)
	}
	return out, total, rows.Err()
}
