package ai

import "time"

type Message struct {
	ID        string
	UserID    string
	Role      string
	Content   string
	CreatedAt time.Time
}
