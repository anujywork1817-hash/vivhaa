package notifications

import "time"

type Notification struct {
	ID        string
	UserID    string
	Type      string
	Title     string
	Body      *string
	Data      []byte // raw JSON
	ReadAt    *time.Time
	CreatedAt time.Time
}
