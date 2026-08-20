package analytics

import "time"

type Event struct {
	ID        string
	EventType string
	UserID    *string
	Metadata  []byte // raw JSON
	CreatedAt time.Time
}
