package visitors

import "time"

// VisitorEntry describes one visit to the profile owner's page, joined
// with a brief of the visitor's own profile.
type VisitorEntry struct {
	VisitorUserID string
	ProfileID     string
	FullName      *string
	City          *string
	PhotoURL      *string
	VisitedAt     time.Time
}
