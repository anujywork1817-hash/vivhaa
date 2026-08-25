package chat

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"time"

	"matrimony-backend/internal/analytics"
	"matrimony-backend/internal/blocked"
	"matrimony-backend/internal/chatguard"
	"matrimony-backend/internal/interests"
	"matrimony-backend/internal/profiles"
	"matrimony-backend/internal/queue"
	"matrimony-backend/internal/subscriptions"
	"matrimony-backend/internal/websocket"
	"matrimony-backend/pkg/ratelimit"
)

var (
	ErrSelfMessage     = errors.New("cannot message yourself")
	ErrChatNotAllowed  = errors.New("chat is only available once you've mutually accepted an interest")
	ErrPremiumRequired = errors.New("upgrade to premium to send messages")
	ErrBlocked         = errors.New("you can't message this member")

	ErrContactRequestPending  = errors.New("you already have a pending contact request with this member")
	ErrContactRequestNotFound = errors.New("contact request not found")
	ErrNotContactRecipient    = errors.New("only the recipient of this request can respond to it")
	ErrContactRequestResolved = errors.New("this contact request has already been responded to")

	// ErrContactInfoBlocked is returned for any message the moderation
	// engine rejects (phone/email/social/link) — the message is NEVER
	// persisted or broadcast. The category/reason is intentionally not
	// exposed here (Phase 15) — see the generic userFacingBlockMessage.
	ErrContactInfoBlocked = errors.New("message blocked by moderation")

	// ErrChatRestricted is returned when the sender is under a temporary
	// send restriction from repeated moderation violations (Phase 14).
	ErrChatRestricted = errors.New("you're temporarily restricted from sending messages")

	ErrEmptyMessage   = errors.New("message body is required")
	ErrMessageTooLong = errors.New("message is too long")
	ErrRateLimited    = errors.New("you're sending messages too quickly — please slow down")
)

// userFacingBlockMessage is the ONLY thing ever shown to a user whose
// message is blocked for containing contact info — no detection
// category, pattern, or reason ever reaches the client (Phase 15).
const userFacingBlockMessage = "Contact details can't be shared through chat yet. You can continue getting to know each other here."

const historyLimit = 50

// contactSharedPaywallBody is shown in place of a contact_shared message's
// real body to a non-premium viewer — computed fresh on every read, never
// stored, so it can never go stale the way a persisted placeholder would.
const contactSharedPaywallBody = "Upgrade to Premium to view the contact number they shared."

type Service struct {
	repo          *Repository
	interestsRepo *interests.Repository
	blockedRepo   *blocked.Repository
	profilesSvc   *profiles.Service
	publisher     *queue.Publisher
	subsSvc       *subscriptions.Service
	analyticsSvc  *analytics.Service
	hub           *websocket.Hub
	guard         *chatguard.Engine
	abuseCfg      AbuseConfig
	limiter       *ratelimit.Limiter
}

// messageRateLimit/messageRateWindow cap how fast an authorized,
// non-blocked, already-matched user can send — every REST send goes
// through Gin's per-route middleware too, but that doesn't cover the
// WebSocket send path (HandleIncoming), which funnels through this same
// SendMessage — without a check here, WS was a completely unthrottled
// spam vector (each send triggers a DB write, Redis publish, analytics
// event, and queued push notification) even between two mutually
// matched, non-blocked users who'd done nothing else wrong.
const (
	messageRateLimit  = 30
	messageRateWindow = time.Minute
)

// AbuseConfig drives the escalating restriction applied to repeated
// moderation violations (Phase 14) — configurable, not hard-coded, so
// thresholds can be tuned without a deploy.
type AbuseConfig struct {
	RestrictThreshold int
	RestrictDuration  time.Duration
	ReviewThreshold   int
}

func NewService(repo *Repository, interestsRepo *interests.Repository, blockedRepo *blocked.Repository, profilesSvc *profiles.Service, publisher *queue.Publisher, subsSvc *subscriptions.Service, analyticsSvc *analytics.Service, hub *websocket.Hub, guard *chatguard.Engine, abuseCfg AbuseConfig, limiter *ratelimit.Limiter) *Service {
	return &Service{repo: repo, interestsRepo: interestsRepo, blockedRepo: blockedRepo, profilesSvc: profilesSvc, publisher: publisher, subsSvc: subsSvc, analyticsSvc: analyticsSvc, hub: hub, guard: guard, abuseCfg: abuseCfg, limiter: limiter}
}

// checkCanSend runs the checks every send path (text, attachment, contact
// request) shares: not messaging yourself, a live mutual match, neither
// side has blocked the other, and sending is premium-gated.
func (s *Service) checkCanSend(ctx context.Context, senderID, receiverID string) error {
	if senderID == receiverID {
		return ErrSelfMessage
	}

	allowed, err := s.interestsRepo.IsAccepted(ctx, senderID, receiverID)
	if err != nil {
		return err
	}
	if !allowed {
		return ErrChatNotAllowed
	}

	isBlocked, err := s.blockedRepo.IsBlocked(ctx, senderID, receiverID)
	if err != nil {
		return err
	}
	if isBlocked {
		return ErrBlocked
	}

	// Sending is premium-gated (the "chat" plan feature — see the
	// subscription_plans seed data); free users can still match, open a
	// conversation and read replies, but must upgrade to send. This was
	// gated here once before and reverted because the frontend's send()
	// silently swallowed the resulting error — this time ErrPremiumRequired
	// is surfaced to the caller (see the ListMessages/SendMessage callers
	// in handler.go) so the UI can show a real paywall instead of a no-op.
	canChat, err := s.subsSvc.HasFeature(ctx, senderID, "chat")
	if err != nil {
		return err
	}
	if !canChat {
		return ErrPremiumRequired
	}

	if s.limiter != nil {
		if err := s.limiter.Allow(ctx, "chat:send:"+senderID, messageRateLimit, messageRateWindow); err != nil {
			var limitErr *ratelimit.LimitExceededError
			if errors.As(err, &limitErr) {
				return ErrRateLimited
			}
			return err
		}
	}
	return nil
}

// maxMessageBodyLen matches the REST handler's validate:"max=4000" tag —
// duplicated here (not read from a shared const in that struct tag) so
// the WebSocket path, which has no validator middleware of its own,
// enforces the identical limit. Without this, a client could send over
// WS instead of REST to submit an empty or up-to-64KB message,
// inconsistent with (and bypassing) the REST limit.
const maxMessageBodyLen = 4000

func (s *Service) SendMessage(ctx context.Context, senderID, receiverID, body string, replyToID *string) (MessageResponse, error) {
	if len(body) == 0 {
		return MessageResponse{}, ErrEmptyMessage
	}
	if len(body) > maxMessageBodyLen {
		return MessageResponse{}, ErrMessageTooLong
	}
	if err := s.checkCanSend(ctx, senderID, receiverID); err != nil {
		return MessageResponse{}, err
	}

	// A reply target must actually belong to this conversation — otherwise
	// fail soft (drop the link, still send the message) rather than reject
	// the whole send over what's a minor UX feature, not a validation the
	// user did anything wrong to trigger (e.g. the quoted message could've
	// been deleted/moderated between the swipe and the send completing).
	var repliedMsg *Message
	if replyToID != nil {
		if replied, err := s.repo.GetMessageByID(ctx, *replyToID, senderID); err == nil &&
			(replied.SenderUserID == senderID || replied.SenderUserID == receiverID) &&
			(replied.ReceiverUserID == senderID || replied.ReceiverUserID == receiverID) {
			repliedMsg = &replied
		} else {
			replyToID = nil
		}
	}

	// Moderation runs BEFORE persistence and BEFORE any WS broadcast — a
	// blocked message is never written to chat_messages and never reaches
	// the other participant. This is the one send path both REST
	// (SendMessage handler) and WebSocket (HandleIncoming below) funnel
	// through, so both are covered by this single check — see Phase 1's
	// architecture note on why this is the correct insertion point.
	if err := s.enforceModeration(ctx, senderID, receiverID, body); err != nil {
		return MessageResponse{}, err
	}

	m, err := s.repo.CreateMessage(ctx, senderID, receiverID, body, MessageKindText, replyToID)
	if err != nil {
		return MessageResponse{}, err
	}

	if repliedMsg != nil {
		m.ReplyToBody = &repliedMsg.Body
		m.ReplyToSenderUserID = &repliedMsg.SenderUserID
	}

	resp := toResponse(m)
	s.pushEvent(receiverID, "message", resp)
	s.pushEvent(senderID, "message", resp)

	_ = s.publisher.PublishNotificationDispatch(ctx, queue.NotificationDispatchEvent{
		UserID: receiverID,
		Type:   "new_message",
		Title:  "New message",
		Body:   truncate(body, 140),
		Data:   map[string]any{"sender_user_id": senderID, "message_id": m.ID},
	})
	_ = s.analyticsSvc.Track(ctx, "message_sent", &senderID, map[string]string{"receiver_user_id": receiverID, "message_id": m.ID})

	return resp, nil
}

// SendAttachment sends an image/document message — same authorization as
// SendMessage, but no text moderation: the contact-info detector only
// ever inspected kind='text' bodies (attachments have no OCR/content
// scanning wired up — see internal/chatguard's ImageModerator doc
// comment for why that's a documented gap, not an oversight), and
// caption is a short filename/label, not free-form user prose worth
// scanning on its own.
func (s *Service) SendAttachment(ctx context.Context, senderID, receiverID, kind, caption, attachmentURL string) (MessageResponse, error) {
	if err := s.checkCanSend(ctx, senderID, receiverID); err != nil {
		return MessageResponse{}, err
	}

	m, err := s.repo.CreateAttachmentMessage(ctx, senderID, receiverID, caption, kind, attachmentURL)
	if err != nil {
		return MessageResponse{}, err
	}

	resp := toResponse(m)
	s.pushEvent(receiverID, "message", resp)
	s.pushEvent(senderID, "message", resp)

	notifBody := "Sent a photo"
	if kind == MessageKindDocument {
		notifBody = "Sent a document"
	}
	_ = s.publisher.PublishNotificationDispatch(ctx, queue.NotificationDispatchEvent{
		UserID: receiverID,
		Type:   "new_message",
		Title:  "New message",
		Body:   notifBody,
		Data:   map[string]any{"sender_user_id": senderID, "message_id": m.ID},
	})
	_ = s.analyticsSvc.Track(ctx, "message_sent", &senderID, map[string]string{"receiver_user_id": receiverID, "message_id": m.ID})

	return resp, nil
}

// RequestContact asks targetID to share their contact number with
// requesterID — it does not reveal anything itself. The request is a chat
// message (kind=contact_request) that targetID must explicitly accept or
// decline via RespondContact; only an accept ever produces the actual
// number, and only to the requester.
func (s *Service) RequestContact(ctx context.Context, requesterID, targetID string) (MessageResponse, error) {
	if requesterID == targetID {
		return MessageResponse{}, ErrSelfMessage
	}

	allowed, err := s.interestsRepo.IsAccepted(ctx, requesterID, targetID)
	if err != nil {
		return MessageResponse{}, err
	}
	if !allowed {
		return MessageResponse{}, ErrChatNotAllowed
	}

	isBlocked, err := s.blockedRepo.IsBlocked(ctx, requesterID, targetID)
	if err != nil {
		return MessageResponse{}, err
	}
	if isBlocked {
		return MessageResponse{}, ErrBlocked
	}

	pending, err := s.repo.HasPendingContactRequest(ctx, requesterID, targetID)
	if err != nil {
		return MessageResponse{}, err
	}
	if pending {
		return MessageResponse{}, ErrContactRequestPending
	}

	m, err := s.repo.CreateMessage(ctx, requesterID, targetID,
		"Requested your contact number.", MessageKindContactRequest, nil)
	if err != nil {
		return MessageResponse{}, err
	}

	resp := toResponse(m)
	s.pushEvent(targetID, "message", resp)
	s.pushEvent(requesterID, "message", resp)

	_ = s.publisher.PublishNotificationDispatch(ctx, queue.NotificationDispatchEvent{
		UserID: targetID,
		Type:   "contact_request",
		Title:  "Contact number request",
		Body:   "Someone would like to share contact numbers with you.",
		Data:   map[string]any{"sender_user_id": requesterID, "message_id": m.ID},
	})

	return resp, nil
}

// RespondContact resolves a pending contact request. On accept, the
// target's phone/email is fetched through profiles.Service (so the
// requester's own premium gate still applies) and delivered as a new
// message visible to both participants; on decline, only the request
// message's status changes — no number is ever touched.
func (s *Service) RespondContact(ctx context.Context, responderID, messageID string, accept bool) (MessageResponse, error) {
	m, err := s.repo.GetMessageByID(ctx, messageID, responderID)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			return MessageResponse{}, ErrContactRequestNotFound
		}
		return MessageResponse{}, err
	}
	if m.Kind != MessageKindContactRequest {
		return MessageResponse{}, ErrContactRequestResolved
	}
	if m.ReceiverUserID != responderID {
		return MessageResponse{}, ErrNotContactRecipient
	}

	// Blocking was only ever checked at the original request time — if
	// either side blocked the other in the meantime, accepting here would
	// still share contact info between them, contradicting the app's
	// blocking guarantee. Declining a blocked request is harmless (no
	// info is shared either way), so this only needs to gate the accept
	// path.
	if accept {
		isBlocked, err := s.blockedRepo.IsBlocked(ctx, m.SenderUserID, m.ReceiverUserID)
		if err != nil {
			return MessageResponse{}, err
		}
		if isBlocked {
			return MessageResponse{}, ErrBlocked
		}
	}

	newKind := MessageKindContactDeclined
	if accept {
		newKind = MessageKindContactAccepted
	}
	if err := s.repo.UpdateMessageKind(ctx, messageID, newKind); err != nil {
		return MessageResponse{}, err
	}
	m.Kind = newKind
	resp := toResponse(m)
	s.pushEvent(m.SenderUserID, "message_updated", resp)
	s.pushEvent(m.ReceiverUserID, "message_updated", resp)

	if !accept {
		_ = s.publisher.PublishNotificationDispatch(ctx, queue.NotificationDispatchEvent{
			UserID: m.SenderUserID,
			Type:   "contact_declined",
			Title:  "Contact request declined",
			Body:   "They declined to share their contact number.",
			Data:   map[string]any{"message_id": m.ID},
		})
		return resp, nil
	}

	// BUG-CRIT-01: this used to run the requester's (m.SenderUserID's)
	// view_contact premium check *before* creating the message, and
	// store its outcome as the message's permanent body — so a
	// non-premium requester's row literally persisted the string
	// "Upgrade to Premium..." forever, with the real number never
	// written down anywhere. Upgrading later couldn't recover it: it
	// was never saved. The responder already consented to share by
	// accepting, so the real value is always fetched and stored now —
	// GetContactInfoRaw is the same lookup GetContactInfo does, minus
	// the premium gate, which belongs at *read* time (below and in
	// GetHistory/ListConversations), not at storage time.
	// BUG: this fetched m.SenderUserID's (the requester's) own contact
	// info instead of responderID's (the target who's actually sharing
	// theirs) — a requester with no phone/email on file got a blank
	// "haven't added a contact number yet" message back even though the
	// responder genuinely had shared a real number, and any requester who
	// DID have contact info on file was handed their own number back
	// instead of the responder's.
	contact, err := s.profilesSvc.GetContactInfoRaw(ctx, responderID)
	var sharedBody string
	if err != nil {
		if !errors.Is(err, profiles.ErrNotFound) {
			return resp, err
		}
		sharedBody = "They accepted, but haven't added a contact number yet."
	} else if contact.Phone != nil && *contact.Phone != "" {
		sharedBody = "Contact number: " + *contact.Phone
	} else if contact.Email != nil && *contact.Email != "" {
		sharedBody = "Contact email: " + *contact.Email
	} else {
		sharedBody = "They accepted, but haven't added a contact number yet."
	}

	shared, err := s.repo.CreateMessage(ctx, responderID, m.SenderUserID, sharedBody, MessageKindContactShared, nil)
	if err != nil {
		return resp, err
	}

	// The requester (m.SenderUserID) only sees the real value live if
	// currently premium — re-checked on every later read too, so
	// upgrading afterward reveals what was actually shared instead of a
	// frozen paywall string. The responder always sees their own shared
	// value: they already know it, and they are the one who agreed to
	// share it.
	requesterResp, err := s.viewerFacingResponse(ctx, m.SenderUserID, shared)
	if err != nil {
		return resp, err
	}
	s.pushEvent(m.SenderUserID, "message", requesterResp)
	s.pushEvent(m.ReceiverUserID, "message", toResponse(shared))

	_ = s.publisher.PublishNotificationDispatch(ctx, queue.NotificationDispatchEvent{
		UserID: m.SenderUserID,
		Type:   "contact_accepted",
		Title:  "Contact number shared",
		Body:   "They accepted your contact request.",
		Data:   map[string]any{"message_id": shared.ID},
	})

	return resp, nil
}

// HandleIncoming parses and processes one inbound WS message from userID,
// pushing an error event back to the sender if it can't be delivered.
func (s *Service) HandleIncoming(ctx context.Context, userID string, raw []byte) {
	var in IncomingWSMessage
	if err := json.Unmarshal(raw, &in); err != nil {
		s.pushEvent(userID, "error", map[string]string{"message": "invalid message payload"})
		return
	}

	if _, err := s.SendMessage(ctx, userID, in.ReceiverUserID, in.Body, in.ReplyToID); err != nil {
		s.pushEvent(userID, "error", map[string]string{"message": err.Error()})
	}
}

func (s *Service) GetHistory(ctx context.Context, userID, partnerID string) ([]MessageResponse, error) {
	messages, err := s.repo.History(ctx, userID, partnerID, historyLimit)
	if err != nil {
		return nil, err
	}

	_ = s.repo.MarkConversationRead(ctx, userID, partnerID)

	// Cached per call: every contact_shared row addressed to userID needs
	// the same premium check, and a conversation can hold more than one
	// (a contact could be requested, declined, and re-requested).
	var hasContactAccessChecked, hasContactAccess bool

	out := make([]MessageResponse, 0, len(messages))
	for _, m := range messages {
		if m.Kind == MessageKindContactShared && m.ReceiverUserID == userID {
			if !hasContactAccessChecked {
				hasContactAccess, err = s.subsSvc.HasFeature(ctx, userID, "view_contact")
				if err != nil {
					return nil, err
				}
				hasContactAccessChecked = true
			}
			if !hasContactAccess {
				m.Body = contactSharedPaywallBody
			}
		}
		out = append(out, toResponse(m))
	}
	return out, nil
}

// viewerFacingResponse masks m's body for viewerID exactly as GetHistory
// does for a single message — used for the live WS push sent to the
// contact-shared message's receiver right when it's created, so what they
// see immediately matches what a later GetHistory call would show them.
func (s *Service) viewerFacingResponse(ctx context.Context, viewerID string, m Message) (MessageResponse, error) {
	if m.Kind == MessageKindContactShared && m.ReceiverUserID == viewerID {
		hasAccess, err := s.subsSvc.HasFeature(ctx, viewerID, "view_contact")
		if err != nil {
			return MessageResponse{}, err
		}
		if !hasAccess {
			m.Body = contactSharedPaywallBody
		}
	}
	return toResponse(m), nil
}

func (s *Service) ListConversations(ctx context.Context, userID string) ([]ConversationResponse, error) {
	rows, err := s.repo.ListConversations(ctx, userID)
	if err != nil {
		return nil, err
	}

	// Same premium check as GetHistory, cached across rows for one caller.
	var hasContactAccessChecked, hasContactAccess bool

	out := make([]ConversationResponse, 0, len(rows))
	for _, r := range rows {
		lastMessage := r.LastMessage
		if r.LastMessageKind == MessageKindContactShared && r.LastMessageReceiverUserID == userID {
			if !hasContactAccessChecked {
				hasContactAccess, err = s.subsSvc.HasFeature(ctx, userID, "view_contact")
				if err != nil {
					return nil, err
				}
				hasContactAccessChecked = true
			}
			if !hasContactAccess {
				lastMessage = contactSharedPaywallBody
			}
		}
		out = append(out, ConversationResponse{
			PartnerUserID:   r.PartnerUserID,
			PartnerName:     r.PartnerName,
			PartnerPhotoURL: r.PartnerPhotoURL,
			LastMessage:     lastMessage,
			LastMessageAt:   r.LastMessageAt.Format(time.RFC3339),
			UnreadCount:     r.UnreadCount,
			IsBlocked:       r.IsBlocked,
		})
	}
	return out, nil
}

func (s *Service) pushEvent(userID, eventType string, data any) {
	payload, err := json.Marshal(OutgoingWSEvent{Type: eventType, Data: data})
	if err != nil {
		slog.Error("chat: failed to marshal outgoing WS event", "event_type", eventType, "error", err)
		return
	}
	s.hub.SendToUser(userID, payload)
}

func toResponse(m Message) MessageResponse {
	resp := MessageResponse{
		ID:             m.ID,
		SenderUserID:   m.SenderUserID,
		ReceiverUserID: m.ReceiverUserID,
		Body:           m.Body,
		Kind:           m.Kind,
		AttachmentURL:  m.AttachmentURL,
		Read:           m.ReadAt != nil,
		CreatedAt:      m.CreatedAt.Format(time.RFC3339),
	}
	if m.ReplyToMessageID != nil && m.ReplyToBody != nil && m.ReplyToSenderUserID != nil {
		resp.ReplyTo = &ReplyToResponse{
			ID:           *m.ReplyToMessageID,
			Body:         truncate(*m.ReplyToBody, 140),
			SenderUserID: *m.ReplyToSenderUserID,
		}
	}
	return resp
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max] + "..."
}
