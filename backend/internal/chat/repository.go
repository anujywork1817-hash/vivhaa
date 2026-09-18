package chat

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("message not found")

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) CreateMessage(ctx context.Context, senderID, receiverID, body, kind string, replyToID *string) (Message, error) {
	return r.createMessage(ctx, senderID, receiverID, body, kind, replyToID, nil)
}

// CreateAttachmentMessage is CreateMessage plus an attachment URL — kept
// as a separate entry point (rather than adding an optional param to
// every CreateMessage caller) since only the image/document send path
// ever has one.
func (r *Repository) CreateAttachmentMessage(ctx context.Context, senderID, receiverID, body, kind, attachmentURL string) (Message, error) {
	return r.createMessage(ctx, senderID, receiverID, body, kind, nil, &attachmentURL)
}

func (r *Repository) createMessage(ctx context.Context, senderID, receiverID, body, kind string, replyToID, attachmentURL *string) (Message, error) {
	const q = `
		INSERT INTO chat_messages (sender_user_id, receiver_user_id, body, kind, reply_to_message_id, attachment_url)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, sender_user_id, receiver_user_id, body, kind, read_at, created_at, reply_to_message_id, attachment_url`
	var m Message
	err := r.db.QueryRow(ctx, q, senderID, receiverID, body, kind, replyToID, attachmentURL).Scan(
		&m.ID, &m.SenderUserID, &m.ReceiverUserID, &m.Body, &m.Kind, &m.ReadAt, &m.CreatedAt,
		&m.ReplyToMessageID, &m.AttachmentURL)
	return m, err
}

// History returns messages between userID and partnerID, oldest first,
// most recent `limit` messages. Excludes rows userID deleted "for me" —
// filtered here (not client-side) so a hidden message never leaves the
// server at all. A message deleted "for everyone" still comes back (both
// sides need to render its "message deleted" placeholder in place, not
// have a gap in the thread) but with Body/AttachmentURL stripped.
func (r *Repository) History(ctx context.Context, userID, partnerID string, limit int) ([]Message, error) {
	const q = `
		SELECT id, sender_user_id, receiver_user_id, body, kind, read_at, created_at,
		       reply_to_message_id, reply_body, reply_sender_user_id, attachment_url, deleted_for_everyone_at FROM (
			SELECT cm.id, cm.sender_user_id, cm.receiver_user_id,
			       CASE WHEN cm.deleted_for_everyone_at IS NOT NULL THEN '' ELSE cm.body END AS body,
			       cm.kind, cm.read_at, cm.created_at,
			       cm.reply_to_message_id, rt.body AS reply_body, rt.sender_user_id AS reply_sender_user_id,
			       CASE WHEN cm.deleted_for_everyone_at IS NOT NULL THEN NULL ELSE cm.attachment_url END AS attachment_url,
			       cm.deleted_for_everyone_at
			FROM chat_messages cm
			LEFT JOIN chat_messages rt ON rt.id = cm.reply_to_message_id
			WHERE ((cm.sender_user_id = $1 AND cm.receiver_user_id = $2) OR (cm.sender_user_id = $2 AND cm.receiver_user_id = $1))
			  AND NOT (cm.sender_user_id = $1 AND cm.sender_deleted_at IS NOT NULL)
			  AND NOT (cm.receiver_user_id = $1 AND cm.receiver_deleted_at IS NOT NULL)
			ORDER BY cm.created_at DESC
			LIMIT $3
		) recent
		ORDER BY created_at ASC`
	rows, err := r.db.Query(ctx, q, userID, partnerID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []Message
	for rows.Next() {
		var m Message
		if err := rows.Scan(
			&m.ID, &m.SenderUserID, &m.ReceiverUserID, &m.Body, &m.Kind, &m.ReadAt, &m.CreatedAt,
			&m.ReplyToMessageID, &m.ReplyToBody, &m.ReplyToSenderUserID, &m.AttachmentURL, &m.DeletedForEveryoneAt,
		); err != nil {
			return nil, err
		}
		messages = append(messages, m)
	}
	return messages, rows.Err()
}

// DeleteForMe hides a message from only requesterUserID's own view —
// mirrors interests' per-party delete (migration 000033): the other
// side's copy is untouched. Silently succeeds if requesterUserID isn't a
// participant or the message doesn't exist, same as everywhere else in
// this file treats "nothing matched" as a no-op rather than an error.
func (r *Repository) DeleteForMe(ctx context.Context, messageID, requesterUserID string) error {
	const q = `
		UPDATE chat_messages SET
			sender_deleted_at = CASE WHEN sender_user_id = $2 THEN now() ELSE sender_deleted_at END,
			receiver_deleted_at = CASE WHEN receiver_user_id = $2 THEN now() ELSE receiver_deleted_at END
		WHERE id = $1 AND (sender_user_id = $2 OR receiver_user_id = $2)`
	_, err := r.db.Exec(ctx, q, messageID, requesterUserID)
	return err
}

// DeleteConversationForMe is DeleteForMe applied to an entire thread —
// same per-party columns, same "only ever touches the requester's own
// view" contract, just every message with partnerUserID at once instead
// of one message ID. The other side's copy of the conversation (and
// their own read/unread state) is completely untouched; if they send a
// new message afterward, the thread simply reappears in the requester's
// list the normal way ListConversations already works.
func (r *Repository) DeleteConversationForMe(ctx context.Context, requesterUserID, partnerUserID string) error {
	const q = `
		UPDATE chat_messages SET
			sender_deleted_at = CASE WHEN sender_user_id = $1 THEN now() ELSE sender_deleted_at END,
			receiver_deleted_at = CASE WHEN receiver_user_id = $1 THEN now() ELSE receiver_deleted_at END
		WHERE (sender_user_id = $1 AND receiver_user_id = $2) OR (sender_user_id = $2 AND receiver_user_id = $1)`
	_, err := r.db.Exec(ctx, q, requesterUserID, partnerUserID)
	return err
}

// DeleteForEveryone is restricted to the original sender by the WHERE
// clause itself (not just a service-layer check) — same defense-in-depth
// reasoning GetMessageByID's doc comment gives for scoping to the
// participant in the query rather than trusting every caller to check
// first. Returns ErrNotFound if requesterUserID isn't that sender (or
// the message doesn't exist), so the service layer can tell "nothing to
// delete" apart from "you're not allowed to."
func (r *Repository) DeleteForEveryone(ctx context.Context, messageID, requesterUserID string) (Message, error) {
	const q = `
		UPDATE chat_messages SET deleted_for_everyone_at = now()
		WHERE id = $1 AND sender_user_id = $2 AND deleted_for_everyone_at IS NULL
		RETURNING id, sender_user_id, receiver_user_id, body, kind, read_at, created_at`
	var m Message
	err := r.db.QueryRow(ctx, q, messageID, requesterUserID).Scan(
		&m.ID, &m.SenderUserID, &m.ReceiverUserID, &m.Body, &m.Kind, &m.ReadAt, &m.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Message{}, ErrNotFound
	}
	return m, err
}

// GetMessageByID fetches a single message, but ONLY if participantUserID
// is its sender or receiver — used by the contact-request accept/decline
// flow and the reply-target lookup to load and validate a message. The
// participant filter lives in the query itself (not left to each caller
// to separately check afterward) specifically so a future caller can't
// forget it and leak an arbitrary message's contents by ID enumeration —
// every existing caller already checked this themselves too, so this is
// defense in depth, not a behavior change for them.
func (r *Repository) GetMessageByID(ctx context.Context, id, participantUserID string) (Message, error) {
	const q = `SELECT id, sender_user_id, receiver_user_id, body, kind, read_at, created_at
	           FROM chat_messages WHERE id = $1 AND (sender_user_id = $2 OR receiver_user_id = $2)`
	var m Message
	err := r.db.QueryRow(ctx, q, id, participantUserID).Scan(
		&m.ID, &m.SenderUserID, &m.ReceiverUserID, &m.Body, &m.Kind, &m.ReadAt, &m.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Message{}, ErrNotFound
	}
	return m, err
}

// UpdateMessageKind flips a message's kind — used to resolve a pending
// contact_request to contact_accepted/contact_declined in place.
func (r *Repository) UpdateMessageKind(ctx context.Context, id, kind string) error {
	const q = `UPDATE chat_messages SET kind = $2 WHERE id = $1`
	tag, err := r.db.Exec(ctx, q, id, kind)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// HasPendingContactRequest reports whether requesterID already has an
// unresolved contact request sent to targetID, so RequestContact can
// reject a duplicate instead of spamming a second one.
func (r *Repository) HasPendingContactRequest(ctx context.Context, requesterID, targetID string) (bool, error) {
	const q = `SELECT EXISTS (
		SELECT 1 FROM chat_messages
		WHERE sender_user_id = $1 AND receiver_user_id = $2 AND kind = 'contact_request'
	)`
	var exists bool
	err := r.db.QueryRow(ctx, q, requesterID, targetID).Scan(&exists)
	return exists, err
}

// ListConversations returns one row per chat partner with the most recent
// message and unread count, newest conversation first. A mutually accepted
// interest unlocks chat immediately (see interests.Repository.IsAccepted /
// chat.Service.SendMessage), so a partner is included here even before any
// message has actually been sent — otherwise the chat window would be
// unreachable from the UI until one of the two users already had a way in,
// a chicken-and-egg gap that used to leave the chat button permanently
// locked despite both sides having accepted.
func (r *Repository) ListConversations(ctx context.Context, userID string) ([]ConversationSummary, error) {
	const q = `
		WITH convo AS (
			SELECT
				CASE WHEN sender_user_id = $1 THEN receiver_user_id ELSE sender_user_id END AS partner_id,
				body, kind, receiver_user_id, created_at,
				ROW_NUMBER() OVER (
					PARTITION BY CASE WHEN sender_user_id = $1 THEN receiver_user_id ELSE sender_user_id END
					ORDER BY created_at DESC
				) AS rn
			FROM chat_messages
			WHERE (sender_user_id = $1 OR receiver_user_id = $1)
			  AND NOT (sender_user_id = $1 AND sender_deleted_at IS NOT NULL)
			  AND NOT (receiver_user_id = $1 AND receiver_deleted_at IS NOT NULL)
		),
		accepted_partners AS (
			SELECT
				CASE WHEN sender_user_id = $1 THEN receiver_user_id ELSE sender_user_id END AS partner_id,
				COALESCE(responded_at, created_at) AS accepted_at
			FROM interests
			WHERE status = 'accepted' AND (sender_user_id = $1 OR receiver_user_id = $1)
		),
		combined AS (
			SELECT partner_id, body, kind, receiver_user_id, created_at FROM convo WHERE rn = 1
			UNION ALL
			SELECT ap.partner_id, '' AS body, '' AS kind, NULL AS receiver_user_id, ap.accepted_at AS created_at
			FROM accepted_partners ap
			WHERE NOT EXISTS (SELECT 1 FROM convo c WHERE c.partner_id = ap.partner_id)
		)
		SELECT
			c.partner_id, p.full_name,
			(SELECT url FROM profile_photos pp WHERE pp.profile_id = p.id ORDER BY pp.is_primary DESC, pp.sort_order ASC LIMIT 1),
			c.body, c.kind, COALESCE(c.receiver_user_id::text, ''), c.created_at,
			(SELECT COUNT(*) FROM chat_messages WHERE receiver_user_id = $1 AND sender_user_id = c.partner_id AND read_at IS NULL AND receiver_deleted_at IS NULL),
			EXISTS (
				SELECT 1 FROM blocked_users b
				WHERE (b.user_id = $1 AND b.blocked_user_id = c.partner_id)
				   OR (b.user_id = c.partner_id AND b.blocked_user_id = $1)
			)
		FROM combined c
		JOIN profiles p ON p.user_id = c.partner_id
		ORDER BY c.created_at DESC`

	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var summaries []ConversationSummary
	for rows.Next() {
		var cs ConversationSummary
		if err := rows.Scan(
			&cs.PartnerUserID, &cs.PartnerName, &cs.PartnerPhotoURL,
			&cs.LastMessage, &cs.LastMessageKind, &cs.LastMessageReceiverUserID,
			&cs.LastMessageAt, &cs.UnreadCount, &cs.IsBlocked,
		); err != nil {
			return nil, err
		}
		summaries = append(summaries, cs)
	}
	return summaries, rows.Err()
}

func (r *Repository) MarkConversationRead(ctx context.Context, userID, partnerID string) error {
	const q = `
		UPDATE chat_messages SET read_at = now()
		WHERE receiver_user_id = $1 AND sender_user_id = $2 AND read_at IS NULL`
	_, err := r.db.Exec(ctx, q, userID, partnerID)
	return err
}
