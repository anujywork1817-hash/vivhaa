package reports

type ReportRequest struct {
	Reason  string  `json:"reason" validate:"required,oneof=fake_profile inappropriate_content harassment spam other"`
	Details *string `json:"details" validate:"omitempty,max=2000"`
}

type Response struct {
	ID             string  `json:"id"`
	ReporterUserID string  `json:"reporter_user_id"`
	ReportedUserID string  `json:"reported_user_id"`
	Reason         string  `json:"reason"`
	Details        *string `json:"details"`
	Status         string  `json:"status"`
	CreatedAt      string  `json:"created_at"`
}
