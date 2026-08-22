package chat

import "time"

// Message kinds. "text" is an ordinary chat message; the rest track a
// contact-number request through its lifecycle. A contact_request message
// is mutated in place to contact_accepted/contact_declined once the
// recipient responds — its own row doubles as the request record, so
// there's no separate requests table. contact_shared is a follow-up
// message created only on accept, carrying the actual phone/email.
const (
	MessageKindText            = "text"
	MessageKindContactRequest  = "contact_request"
	MessageKindContactAccepted = "contact_accepted"
	MessageKindContactDeclined = "contact_declined"
	MessageKindContactShared   = "contact_shared"
)

type Message struct {
	ID             string
	SenderUserID   string
	ReceiverUserID string
	Body           string
	Kind           string
	ReadAt         *time.Time
	CreatedAt      time.Time
}

// ConversationSummary describes one chat partner for a conversation list.
type ConversationSummary struct {
	PartnerUserID   string
	PartnerName     *string
	PartnerPhotoURL *string
	LastMessage     string
	// LastMessageKind and LastMessageReceiverUserID exist only so the
	// service layer can decide whether LastMessage needs the same
	// premium-gate masking GetHistory applies to a contact_shared
	// message — otherwise the inbox preview would show a shared contact
	// number in plaintext even to a non-premium viewer.
	LastMessageKind           string
	LastMessageReceiverUserID string
	LastMessageAt             time.Time
	UnreadCount               int
	// IsBlocked is true when either side has blocked the other. The
	// conversation still appears (message history isn't deleted on
	// block, so hiding it would look like it vanished) — the frontend
	// uses this to mark it as blocked and disable messaging instead.
	IsBlocked bool
}
