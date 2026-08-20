package notifications

type Response struct {
	ID        string  `json:"id"`
	Type      string  `json:"type"`
	Title     string  `json:"title"`
	Body      *string `json:"body"`
	Data      any     `json:"data,omitempty"`
	Read      bool    `json:"read"`
	CreatedAt string  `json:"created_at"`
}

type ListResponse struct {
	Notifications []Response `json:"notifications"`
	UnreadCount   int        `json:"unread_count"`
}
