package calls

import "encoding/json"

// IncomingCallMessage is the shape of every call:* message a client sends
// over the shared /ws/chat connection. Offer/Answer/Candidate are kept as
// opaque JSON — the server relays WebRTC SDP/ICE payloads verbatim without
// needing to understand their contents.
type IncomingCallMessage struct {
	Type         string          `json:"type"`
	CalleeID     string          `json:"callee_id,omitempty"`
	CallID       string          `json:"call_id,omitempty"`
	TargetUserID string          `json:"target_user_id,omitempty"`
	// IsVideo distinguishes a video call from an audio-only one. Only
	// meaningful (and only read) on call:initiate — every other message
	// type refers back to a call whose kind was already fixed at
	// creation. Defaults to true (json's zero value for a missing bool
	// is false, but every call before this field existed was a video
	// call — see Service.initiate for where the default is applied).
	IsVideo   *bool           `json:"is_video,omitempty"`
	Offer     json.RawMessage `json:"offer,omitempty"`
	Answer    json.RawMessage `json:"answer,omitempty"`
	Candidate json.RawMessage `json:"candidate,omitempty"`
	Reason    string          `json:"reason,omitempty"`
}

type ICEServer struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

type ICEServersResponse struct {
	ICEServers []ICEServer `json:"ice_servers"`
}

// CallHistoryResponse is one row of GET /admin/call-history.
type CallHistoryResponse struct {
	ID              string  `json:"id"`
	CallerUserID    string  `json:"caller_user_id"`
	CallerName      *string `json:"caller_name"`
	CalleeUserID    string  `json:"callee_user_id"`
	CalleeName      *string `json:"callee_name"`
	Status          string  `json:"status"`
	IsVideo         bool    `json:"is_video"`
	StartedAt       string  `json:"started_at"`
	EndedAt         *string `json:"ended_at"`
	DurationSeconds *int    `json:"duration_seconds"`
	EndReason       *string `json:"end_reason"`
}

// MyCallHistoryResponse is one row of GET /calls/history — from the
// caller's own point of view, so it names the *other* party once
// (PartnerUserID/PartnerName/PartnerPhoto) plus Direction, rather than
// making the client figure out which of caller/callee is "me".
type MyCallHistoryResponse struct {
	ID              string  `json:"id"`
	PartnerUserID   string  `json:"partner_user_id"`
	PartnerName     *string `json:"partner_name"`
	PartnerPhoto    *string `json:"partner_photo"`
	Direction       string  `json:"direction"` // "outgoing" | "incoming"
	Status          string  `json:"status"`
	IsVideo         bool    `json:"is_video"`
	StartedAt       string  `json:"started_at"`
	EndedAt         *string `json:"ended_at"`
	DurationSeconds *int    `json:"duration_seconds"`
	EndReason       *string `json:"end_reason"`
}

type ListMeta struct {
	Page  int `json:"page"`
	Limit int `json:"limit"`
	Total int `json:"total"`
}
