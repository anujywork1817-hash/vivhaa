package moderation

import "time"

type Report struct {
	ID             string
	ReporterUserID string
	ReportedUserID string
	Reason         string
	Details        *string
	Category       string
	Priority       string
	Status         string
	ReviewedBy     *string
	ReviewNotes    *string
	CreatedAt      time.Time
	ReviewedAt     *time.Time

	// Joined in for the admin queue — nil if either profile is somehow
	// missing (e.g. a deleted account), in which case the UI falls back
	// to showing the raw user ID.
	ReporterName *string
	ReportedName *string
}
