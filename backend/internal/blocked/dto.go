package blocked

type Response struct {
	ID            string `json:"id"`
	UserID        string `json:"user_id"`
	BlockedUserID string `json:"blocked_user_id"`
	CreatedAt     string `json:"created_at"`

	ProfileID string  `json:"profile_id,omitempty"`
	FullName  *string `json:"full_name,omitempty"`
	City      *string `json:"city,omitempty"`
	PhotoURL  *string `json:"photo_url,omitempty"`
}

// StatusResponse is the block relationship between the caller and a given
// profile, checked independently in each direction so the UI can show
// "you blocked them" (with an unblock action) distinctly from "they
// blocked you" (no action available).
type StatusResponse struct {
	IsBlockedByMe bool `json:"is_blocked_by_me"`
	HasBlockedMe  bool `json:"has_blocked_me"`
}
