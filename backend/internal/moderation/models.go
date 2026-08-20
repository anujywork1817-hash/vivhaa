package moderation

import "time"

type Report struct {
	ID             string
	ReporterUserID string
	ReportedUserID string
	Reason         string
	Details        *string
	Status         string
	ReviewedBy     *string
	ReviewNotes    *string
	CreatedAt      time.Time
	ReviewedAt     *time.Time
}
