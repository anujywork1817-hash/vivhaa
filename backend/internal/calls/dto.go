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

// CallStatusResponse backs GET /calls/:call_id/status — a deterministic
// backstop against the call:end WebSocket push getting silently dropped
// (Redis pub/sub is fire-and-forget; a subscriber with a momentary
// connection blip at the wrong instant never sees it and would otherwise
// only notice via WebRTC's own, much slower ICE-degradation detection).
// The client polls this while a call is connected so a call the server
// already knows is over gets caught within one poll interval rather than
// depending on the dropped push eventually being noticed some other way.
type CallStatusResponse struct {
	Status string `json:"status"` // ringing, ongoing, completed, missed, rejected, failed
	Active bool   `json:"active"` // true only for ringing/ongoing
	// EndReason mirrors the same "reason" call:end already carries, so a
	// stale client learns *why* the call it thought was still connected
	// actually ended, not just that it did.
	EndReason *string `json:"end_reason"`
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
