package reports

// Reason is checked against reasonCatalog (taxonomy.go) in Service.Submit
// rather than a `validate:"oneof=..."` tag — the catalog is large enough,
// and needs enough metadata (category/priority) per entry, that a plain
// enum tag stopped being the right tool.
type ReportRequest struct {
	Reason  string  `json:"reason" validate:"required"`
	Details *string `json:"details" validate:"omitempty,max=2000"`
}

type Response struct {
	ID             string  `json:"id"`
	ReporterUserID string  `json:"reporter_user_id"`
	ReportedUserID string  `json:"reported_user_id"`
	Reason         string  `json:"reason"`
	Details        *string `json:"details"`
	Category       string  `json:"category"`
	Priority       string  `json:"priority"`
	Status         string  `json:"status"`
	CreatedAt      string  `json:"created_at"`
}
