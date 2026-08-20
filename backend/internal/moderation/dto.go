package moderation

type Response struct {
	ID             string  `json:"id"`
	ReporterUserID string  `json:"reporter_user_id"`
	ReportedUserID string  `json:"reported_user_id"`
	Reason         string  `json:"reason"`
	Details        *string `json:"details"`
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
