package calls

import "time"

type CallSession struct {
	ID              string
	CallerUserID    string
	CalleeUserID    string
	Status          string
	IsVideo         bool
	StartedAt       time.Time
	ConnectedAt     *time.Time
	EndedAt         *time.Time
	DurationSeconds *int
	EndReason       *string
}

// CallSessionWithProfiles joins a session with both participants' display
// name, for the admin call-history list.
type CallSessionWithProfiles struct {
	CallSession
	CallerName *string
	CalleeName *string
}

// CallSessionWithPartner joins a session with just the *other* party's
// display name and photo (the caller already knows who they are), for a
// user's own call-history list.
type CallSessionWithPartner struct {
	CallSession
	PartnerName  *string
	PartnerPhoto *string
}
