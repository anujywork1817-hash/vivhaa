package verification

type Response struct {
	ID           string  `json:"id"`
	UserID       string  `json:"user_id"`
	DocumentType string  `json:"document_type"`
	DocumentURL  string  `json:"document_url"`
	Status       string  `json:"status"`
	ReviewNotes  *string `json:"review_notes"`
	CreatedAt    string  `json:"created_at"`
	ReviewedAt   *string `json:"reviewed_at"`
}

type ReviewRequest struct {
	Notes *string `json:"notes"`
}

// ListMeta mirrors admin.ListUsersMeta's shape so every paginated admin
// list response looks the same on the wire.
type ListMeta struct {
	Page  int `json:"page"`
	Limit int `json:"limit"`
	Total int `json:"total"`
}
