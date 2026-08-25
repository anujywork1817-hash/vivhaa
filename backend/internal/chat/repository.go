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
// most recent `limit` messages.
func (r *Repository) History(ctx context.Context, userID, partnerID string, limit int) ([]Message, error) {
	const q = `
		SELECT id, sender_user_id, receiver_user_id, body, kind, read_at, created_at,
		       reply_to_message_id, reply_body, reply_sender_user_id, attachment_url FROM (
			SELECT cm.id, cm.sender_user_id, cm.receiver_user_id, cm.body, cm.kind, cm.read_at, cm.created_at,
			       cm.reply_to_message_id, rt.body AS reply_body, rt.sender_user_id AS reply_sender_user_id,
			       cm.attachment_url
			FROM chat_messages cm
			LEFT JOIN chat_messages rt ON rt.id = cm.reply_to_message_id
			WHERE (cm.sender_user_id = $1 AND cm.receiver_user_id = $2) OR (cm.sender_user_id = $2 AND cm.receiver_user_id = $1)
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
			&m.ReplyToMessageID, &m.ReplyToBody, &m.ReplyToSenderUserID, &m.AttachmentURL,
		); err != nil {
			return nil, err
		}
		messages = append(messages, m)
	}
	return messages, rows.Err()
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
			WHERE sender_user_id = $1 OR receiver_user_id = $1
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
			(SELECT COUNT(*) FROM chat_messages WHERE receiver_user_id = $1 AND sender_user_id = c.partner_id AND read_at IS NULL),
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
