package chat

type MessageResponse struct {
	ID             string           `json:"id"`
	SenderUserID   string           `json:"sender_user_id"`
	ReceiverUserID string           `json:"receiver_user_id"`
	Body           string           `json:"body"`
	Kind           string           `json:"kind"`
	AttachmentURL  *string          `json:"attachment_url,omitempty"`
	Read           bool             `json:"read"`
	CreatedAt      string           `json:"created_at"`
	ReplyTo        *ReplyToResponse `json:"reply_to,omitempty"`
}

// ReplyToResponse is a brief snapshot of the message being replied to —
// just enough for the client to render the quoted preview (swipe-to-reply,
// WhatsApp-style) without a second round trip to fetch the original.
type ReplyToResponse struct {
	ID           string `json:"id"`
	Body         string `json:"body"`
	SenderUserID string `json:"sender_user_id"`
}

type ConversationResponse struct {
	PartnerUserID   string  `json:"partner_user_id"`
	PartnerName     *string `json:"partner_name"`
	PartnerPhotoURL *string `json:"partner_photo_url"`
	LastMessage     string  `json:"last_message"`
	LastMessageAt   string  `json:"last_message_at"`
	UnreadCount     int     `json:"unread_count"`
	IsBlocked       bool    `json:"is_blocked"`
}

// IncomingWSMessage is the JSON payload a client sends over the WS
// connection to send a chat message: {"receiver_user_id": "...", "body": "..."}
type IncomingWSMessage struct {
	ReceiverUserID string  `json:"receiver_user_id"`
	Body           string  `json:"body"`
	ReplyToID      *string `json:"reply_to_message_id,omitempty"`
}

// OutgoingWSEvent is the JSON payload pushed to clients over the WS
// connection, e.g. {"type":"message","data":{...}} or {"type":"error","data":{"message":"..."}}
type OutgoingWSEvent struct {
	Type string `json:"type"`
	Data any    `json:"data"`
}
