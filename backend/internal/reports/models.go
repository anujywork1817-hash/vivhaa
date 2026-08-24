package reports

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
	CreatedAt      time.Time
}
