package interests

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNotFound      = errors.New("not found")
	ErrAlreadyExists = errors.New("interest already expressed")
)

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

// IsAccepted reports whether an accepted, still-live interest exists
// between the two users, regardless of who sent it originally. Excludes
// soft-deleted interests (BUG-H09) — an "unmatch" (Delete) must actually
// revoke chat/call access immediately, not just hide the interest from
// Inbox while the underlying accepted row keeps gating access open.
// Deliberately stays symmetric (deleted by *either* side counts) even
// though list visibility below is now per-party — this is the "did an
// unmatch happen" check, not "is it in my inbox".
func (r *Repository) IsAccepted(ctx context.Context, userA, userB string) (bool, error) {
	const q = `
		SELECT EXISTS (
			SELECT 1 FROM interests
			WHERE status = 'accepted'
			  AND sender_deleted_at IS NULL AND receiver_deleted_at IS NULL
			  AND ((sender_user_id = $1 AND receiver_user_id = $2) OR (sender_user_id = $2 AND receiver_user_id = $1))
		)`
	var exists bool
	err := r.db.QueryRow(ctx, q, userA, userB).Scan(&exists)
	return exists, err
}

func (r *Repository) Create(ctx context.Context, senderID, receiverID string) (Interest, error) {
	const q = `
		INSERT INTO interests (sender_user_id, receiver_user_id)
		VALUES ($1, $2)
		RETURNING id, sender_user_id, receiver_user_id, status, created_at, responded_at, viewed_at`
	var i Interest
	err := r.db.QueryRow(ctx, q, senderID, receiverID).Scan(
		&i.ID, &i.SenderUserID, &i.ReceiverUserID, &i.Status, &i.CreatedAt, &i.RespondedAt, &i.ViewedAt)
	if isUniqueViolation(err) {
		return Interest{}, ErrAlreadyExists
	}
	return i, err
}

// GetByID excludes soft-deleted interests (BUG-H09) — once an interest is
// deleted (unmatched) by *either* side, it must look gone to
// Accept/Decline/Remind too, not just to the list views (which are
// per-party — see ListSent/ListReceived/ListDeleted below).
func (r *Repository) GetByID(ctx context.Context, id string) (Interest, error) {
	const q = `
		SELECT id, sender_user_id, receiver_user_id, status, created_at, responded_at, viewed_at
		FROM interests WHERE id = $1 AND sender_deleted_at IS NULL AND receiver_deleted_at IS NULL`
	var i Interest
	err := r.db.QueryRow(ctx, q, id).Scan(
		&i.ID, &i.SenderUserID, &i.ReceiverUserID, &i.Status, &i.CreatedAt, &i.RespondedAt, &i.ViewedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Interest{}, ErrNotFound
	}
	return i, err
}

func (r *Repository) UpdateStatus(ctx context.Context, id, status string) (Interest, error) {
	const q = `
		UPDATE interests SET status = $2, responded_at = now()
		WHERE id = $1
		RETURNING id, sender_user_id, receiver_user_id, status, created_at, responded_at, viewed_at`
	var i Interest
	err := r.db.QueryRow(ctx, q, id, status).Scan(
		&i.ID, &i.SenderUserID, &i.ReceiverUserID, &i.Status, &i.CreatedAt, &i.RespondedAt, &i.ViewedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Interest{}, ErrNotFound
	}
	return i, err
}

// ListSent returns interests the given user sent, joined with the
// receiver's profile brief.
// ListSent excludes any receiver blocked in either direction — see
// favourites.Repository.List for why this filters rather than deletes.
func (r *Repository) ListSent(ctx context.Context, userID string) ([]InterestWithProfile, error) {
	const q = `
		SELECT i.id, i.sender_user_id, i.receiver_user_id, i.status, i.created_at, i.responded_at, i.viewed_at,
		       p.id, p.full_name, p.gender, p.city, p.state, p.mother_tongue, p.community,
		       (SELECT url FROM profile_photos pp WHERE pp.profile_id = p.id ORDER BY pp.is_primary DESC, pp.sort_order ASC LIMIT 1),
		       p.date_of_birth, p.height_cm, p.marital_status, p.religion, p.education, p.occupation, p.diet, p.manglik
		FROM interests i
		JOIN profiles p ON p.user_id = i.receiver_user_id
		WHERE i.sender_user_id = $1 AND i.sender_deleted_at IS NULL
		  AND NOT EXISTS (
		      SELECT 1 FROM blocked_users b
		      WHERE (b.user_id = $1 AND b.blocked_user_id = i.receiver_user_id)
		         OR (b.user_id = i.receiver_user_id AND b.blocked_user_id = $1)
		  )
		ORDER BY i.created_at DESC`
	return r.listWithProfile(ctx, q, userID)
}

// ListReceived returns interests the given user received, joined with the
// sender's profile brief. Excludes any sender blocked in either direction.
func (r *Repository) ListReceived(ctx context.Context, userID string) ([]InterestWithProfile, error) {
	const q = `
		SELECT i.id, i.sender_user_id, i.receiver_user_id, i.status, i.created_at, i.responded_at, i.viewed_at,
		       p.id, p.full_name, p.gender, p.city, p.state, p.mother_tongue, p.community,
		       (SELECT url FROM profile_photos pp WHERE pp.profile_id = p.id ORDER BY pp.is_primary DESC, pp.sort_order ASC LIMIT 1),
		       p.date_of_birth, p.height_cm, p.marital_status, p.religion, p.education, p.occupation, p.diet, p.manglik
		FROM interests i
		JOIN profiles p ON p.user_id = i.sender_user_id
		WHERE i.receiver_user_id = $1 AND i.receiver_deleted_at IS NULL
		  AND NOT EXISTS (
		      SELECT 1 FROM blocked_users b
		      WHERE (b.user_id = $1 AND b.blocked_user_id = i.sender_user_id)
		         OR (b.user_id = i.sender_user_id AND b.blocked_user_id = $1)
		  )
		ORDER BY i.created_at DESC`
	return r.listWithProfile(ctx, q, userID)
}

// ListDeleted returns interests userID personally removed, from either
// side, joined with the other party's profile — the Inbox > More >
// Deleted list. Per-party: userID's own deleted_at column is what's
// checked on each side, so a request the *other* party deleted (but
// userID never touched) correctly stays out of this list instead of
// showing up as if userID had deleted it themselves.
func (r *Repository) ListDeleted(ctx context.Context, userID string) ([]InterestWithProfile, error) {
	const q = `
		SELECT i.id, i.sender_user_id, i.receiver_user_id, i.status, i.created_at, i.responded_at, i.viewed_at,
		       p.id, p.full_name, p.gender, p.city, p.state, p.mother_tongue, p.community,
		       (SELECT url FROM profile_photos pp WHERE pp.profile_id = p.id ORDER BY pp.is_primary DESC, pp.sort_order ASC LIMIT 1),
		       p.date_of_birth, p.height_cm, p.marital_status, p.religion, p.education, p.occupation, p.diet, p.manglik
		FROM interests i
		JOIN profiles p ON p.user_id = CASE
		         WHEN i.sender_user_id = $1 THEN i.receiver_user_id
		         ELSE i.sender_user_id
		     END
		WHERE (i.sender_user_id = $1 AND i.sender_deleted_at IS NOT NULL)
		   OR (i.receiver_user_id = $1 AND i.receiver_deleted_at IS NOT NULL)
		ORDER BY GREATEST(COALESCE(i.sender_deleted_at, i.receiver_deleted_at),
		                   COALESCE(i.receiver_deleted_at, i.sender_deleted_at)) DESC`
	return r.listWithProfile(ctx, q, userID)
}

// MarkReceivedViewed stamps every still-unseen interest addressed to
// userID as viewed. Called when they list their received interests, which
// is the point the sender's "Viewed / Not viewed yet" indicator should
// flip. Only touches NULL rows so the original timestamp is preserved.
func (r *Repository) MarkReceivedViewed(ctx context.Context, userID string) error {
	const q = `UPDATE interests SET viewed_at = now() WHERE receiver_user_id = $1 AND viewed_at IS NULL AND receiver_deleted_at IS NULL`
	_, err := r.db.Exec(ctx, q, userID)
	return err
}

// Delete soft-deletes an interest for userID's own side only — otherwise
// anyone could delete anyone else's requests by guessing an id, and (the
// actual bug this fixed) a delete from one side must not make the
// request vanish from the OTHER party's inbox too. The row itself is
// kept either way so it can still be listed under Inbox > More >
// Deleted for whichever side actually deleted it.
func (r *Repository) Delete(ctx context.Context, id, userID string) error {
	const q = `
		UPDATE interests SET
			sender_deleted_at = CASE WHEN sender_user_id = $2 THEN now() ELSE sender_deleted_at END,
			receiver_deleted_at = CASE WHEN receiver_user_id = $2 THEN now() ELSE receiver_deleted_at END
		WHERE id = $1
		  AND ((sender_user_id = $2 AND sender_deleted_at IS NULL)
		    OR (receiver_user_id = $2 AND receiver_deleted_at IS NULL))`
	tag, err := r.db.Exec(ctx, q, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) listWithProfile(ctx context.Context, q, userID string) ([]InterestWithProfile, error) {
	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []InterestWithProfile
	for rows.Next() {
		var iwp InterestWithProfile
		if err := rows.Scan(
			&iwp.ID, &iwp.SenderUserID, &iwp.ReceiverUserID, &iwp.Status, &iwp.CreatedAt, &iwp.RespondedAt, &iwp.ViewedAt,
			&iwp.ProfileID, &iwp.FullName, &iwp.Gender, &iwp.City, &iwp.State, &iwp.MotherTongue, &iwp.Community, &iwp.PhotoURL,
			&iwp.DateOfBirth, &iwp.HeightCM, &iwp.MaritalStatus, &iwp.Religion, &iwp.Education, &iwp.Occupation, &iwp.Diet, &iwp.Manglik,
		); err != nil {
			return nil, err
		}
		results = append(results, iwp)
	}
	return results, rows.Err()
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
