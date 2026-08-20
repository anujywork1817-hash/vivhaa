package visitors

import (
	"context"
	"time"
)

const defaultLimit = 50

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) RecordVisit(ctx context.Context, visitorID, visitedID string) error {
	if visitorID == visitedID {
		return nil
	}
	return s.repo.RecordVisit(ctx, visitorID, visitedID)
}

func (s *Service) ListVisitors(ctx context.Context, userID string) ([]Response, error) {
	entries, err := s.repo.ListVisitors(ctx, userID, defaultLimit)
	if err != nil {
		return nil, err
	}

	out := make([]Response, 0, len(entries))
	for _, e := range entries {
		out = append(out, Response{
			VisitorUserID: e.VisitorUserID,
			ProfileID:     e.ProfileID,
			FullName:      e.FullName,
			City:          e.City,
			PhotoURL:      e.PhotoURL,
			VisitedAt:     e.VisitedAt.Format(time.RFC3339),
		})
	}
	return out, nil
}
