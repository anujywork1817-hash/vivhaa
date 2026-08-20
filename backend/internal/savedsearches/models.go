package savedsearches

import (
	"encoding/json"
	"time"
)

type SavedSearch struct {
	ID          string
	UserID      string
	Name        string
	Filters     json.RawMessage
	ResultCount int
	CreatedAt   time.Time
}
