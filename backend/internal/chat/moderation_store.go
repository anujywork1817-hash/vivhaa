package chat

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// moderation_store.go persists moderation.Result outcomes and drives the
// escalating abuse-restriction state (Phase 14/16/21). Kept as a
// dedicated file within the chat package rather than a new package: this
// state is meaningless outside the chat send path that produces it, the
// same way blocked_users/reports are dedicated tables owned by their own
// feature packages while chat_messages stays in chat.

// Restriction is one user's current abuse state.
type Restriction struct {
	ViolationCount   int
	RestrictedUntil  *time.Time
	FlaggedForReview bool
}

// IsRestricted reports whether the user is currently blocked from
// sending due to abuse, as of now.
func (r Restriction) IsRestricted(now time.Time) bool {
	return r.RestrictedUntil != nil && r.RestrictedUntil.After(now)
}

// LogModerationEvent records one moderation decision for observability
// (Phase 21). It deliberately takes only category/decision labels, never
// the message body or any extracted contact info -- see chatguard's
// package doc for why raw contact data must never reach application logs
// or this table.
func (r *Repository) LogModerationEvent(ctx context.Context, userID string, partnerID, messageID *string, category, decision string) error {
	const q = `
		INSERT INTO moderation_events (user_id, partner_user_id, message_id, category, decision)
		VALUES ($1, $2, $3, $4, $5)`
	_, err := r.db.Exec(ctx, q, userID, partnerID, messageID, category, decision)
	return err
}

// GetRestriction loads userID's current abuse state, defaulting to a
// zero-value (no violations, no restriction) if no row exists yet.
func (r *Repository) GetRestriction(ctx context.Context, userID string) (Restriction, error) {
	const q = `SELECT violation_count, restricted_until, flagged_for_review FROM chat_restrictions WHERE user_id = $1`
	var rr Restriction
	err := r.db.QueryRow(ctx, q, userID).Scan(&rr.ViolationCount, &rr.RestrictedUntil, &rr.FlaggedForReview)
	if err == pgx.ErrNoRows {
		return Restriction{}, nil
	}
	return rr, err
}

// RecordViolation atomically increments userID's violation counter
// (creating the row on first offense) and returns the new total -- an
// atomic UPSERT rather than read-then-write, so two simultaneous
// violations from the same user (e.g. two blocked sends racing on
// different API instances) can't both read the same starting count and
// silently drop one increment.
func (r *Repository) RecordViolation(ctx context.Context, userID string) (int, error) {
	const q = `
		INSERT INTO chat_restrictions (user_id, violation_count, updated_at)
		VALUES ($1, 1, now())
		ON CONFLICT (user_id) DO UPDATE
			SET violation_count = chat_restrictions.violation_count + 1, updated_at = now()
		RETURNING violation_count`
	var count int
	err := r.db.QueryRow(ctx, q, userID).Scan(&count)
	return count, err
}

// ApplyRestriction sets (or clears, when until is nil) a temporary send
// restriction and/or the review flag for userID.
func (r *Repository) ApplyRestriction(ctx context.Context, userID string, until *time.Time, flagForReview bool) error {
	const q = `
		INSERT INTO chat_restrictions (user_id, violation_count, restricted_until, flagged_for_review, updated_at)
		VALUES ($1, 0, $2, $3, now())
		ON CONFLICT (user_id) DO UPDATE
			SET restricted_until = $2,
			    flagged_for_review = chat_restrictions.flagged_for_review OR $3,
			    updated_at = now()`
	_, err := r.db.Exec(ctx, q, userID, until, flagForReview)
	return err
}
