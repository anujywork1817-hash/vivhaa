package visitors

type Response struct {
	VisitorUserID string  `json:"visitor_user_id"`
	ProfileID     string  `json:"profile_id"`
	FullName      *string `json:"full_name"`
	City          *string `json:"city"`
	PhotoURL      *string `json:"photo_url"`
	VisitedAt     string  `json:"visited_at"`
}
