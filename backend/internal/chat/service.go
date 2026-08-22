package chat

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"matrimony-backend/internal/analytics"
	"matrimony-backend/internal/blocked"
	"matrimony-backend/internal/interests"
	"matrimony-backend/internal/profiles"
	"matrimony-backend/internal/queue"
	"matrimony-backend/internal/subscriptions"
	"matrimony-backend/internal/websocket"
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
)

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
}

func NewService(repo *Repository, interestsRepo *interests.Repository, blockedRepo *blocked.Repository, profilesSvc *profiles.Service, publisher *queue.Publisher, subsSvc *subscriptions.Service, analyticsSvc *analytics.Service, hub *websocket.Hub) *Service {
	return &Service{repo: repo, interestsRepo: interestsRepo, blockedRepo: blockedRepo, profilesSvc: profilesSvc, publisher: publisher, subsSvc: subsSvc, analyticsSvc: analyticsSvc, hub: hub}
}

func (s *Service) SendMessage(ctx context.Context, senderID, receiverID, body string, replyToID *string) (MessageResponse, error) {
	if senderID == receiverID {
		return MessageResponse{}, ErrSelfMessage
	}

	allowed, err := s.interestsRepo.IsAccepted(ctx, senderID, receiverID)
	if err != nil {
		return MessageResponse{}, err
	}
	if !allowed {
		return MessageResponse{}, ErrChatNotAllowed
	}

	isBlocked, err := s.blockedRepo.IsBlocked(ctx, senderID, receiverID)
	if err != nil {
		return MessageResponse{}, err
	}
	if isBlocked {
		return MessageResponse{}, ErrBlocked
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
		return MessageResponse{}, err
	}
	if !canChat {
		return MessageResponse{}, ErrPremiumRequired
	}

	// A reply target must actually belong to this conversation — otherwise
	// fail soft (drop the link, still send the message) rather than reject
	// the whole send over what's a minor UX feature, not a validation the
	// user did anything wrong to trigger (e.g. the quoted message could've
	// been deleted/moderated between the swipe and the send completing).
	var repliedMsg *Message
	if replyToID != nil {
		if replied, err := s.repo.GetMessageByID(ctx, *replyToID); err == nil &&
			(replied.SenderUserID == senderID || replied.SenderUserID == receiverID) &&
			(replied.ReceiverUserID == senderID || replied.ReceiverUserID == receiverID) {
			repliedMsg = &replied
		} else {
			replyToID = nil
		}
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
	m, err := s.repo.GetMessageByID(ctx, messageID)
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
