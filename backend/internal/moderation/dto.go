package moderation

type Response struct {
	ID             string  `json:"id"`
	ReporterUserID string  `json:"reporter_user_id"`
	ReportedUserID string  `json:"reported_user_id"`
	ReporterName   *string `json:"reporter_name"`
	ReportedName   *string `json:"reported_name"`
	Reason         string  `json:"reason"`
	ReasonLabel    string  `json:"reason_label"`
	Details        *string `json:"details"`
	Category       string  `json:"category"`
	Priority       string  `json:"priority"`
	Status         string  `json:"status"`
	ReviewNotes    *string `json:"review_notes"`
	CreatedAt      string  `json:"created_at"`
	ReviewedAt     *string `json:"reviewed_at"`
}

type ResolveRequest struct {
	Status      string  `json:"status" validate:"required,oneof=reviewed dismissed action_taken"`
	Notes       *string `json:"notes"`
	SuspendUser bool    `json:"suspend_user"`
}

// ListMeta mirrors admin.ListUsersMeta's shape so every paginated admin
// list response looks the same on the wire.
type ListMeta struct {
	Page  int `json:"page"`
	Limit int `json:"limit"`
	Total int `json:"total"`
}
