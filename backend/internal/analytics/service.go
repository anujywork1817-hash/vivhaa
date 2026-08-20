package analytics

import (
	"context"
	"encoding/json"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// Track records an event. Failures are the caller's concern to decide
// whether to surface (event tracking should rarely block the primary
// action it's attached to).
func (s *Service) Track(ctx context.Context, eventType string, userID *string, metadata any) error {
	var raw []byte
	if metadata != nil {
		encoded, err := json.Marshal(metadata)
		if err != nil {
			return err
		}
		raw = encoded
	}
	return s.repo.Create(ctx, eventType, userID, raw)
}
