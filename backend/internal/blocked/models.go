package blocked

import "time"

type BlockedUser struct {
	ID            string
	UserID        string
	BlockedUserID string
	CreatedAt     time.Time
}

// BlockedWithProfile joins a block entry with a brief of the blocked
// party's profile, for list views.
type BlockedWithProfile struct {
	BlockedUser
	ProfileID string
	FullName  *string
	City      *string
	PhotoURL  *string
}
