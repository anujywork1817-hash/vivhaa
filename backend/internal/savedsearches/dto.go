package savedsearches

import "encoding/json"

type CreateRequest struct {
	Name        string          `json:"name" validate:"required,max=100"`
	Filters     json.RawMessage `json:"filters" validate:"required"`
	ResultCount int             `json:"result_count" validate:"gte=0"`
}

type Response struct {
	ID          string          `json:"id"`
	Name        string          `json:"name"`
	Filters     json.RawMessage `json:"filters"`
	ResultCount int             `json:"result_count"`
	CreatedAt   string          `json:"created_at"`
}
