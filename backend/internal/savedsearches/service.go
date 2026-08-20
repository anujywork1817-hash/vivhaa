package savedsearches

import (
	"context"
	"time"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) Create(ctx context.Context, userID string, req CreateRequest) (Response, error) {
	saved, err := s.repo.Create(ctx, userID, req.Name, req.Filters, req.ResultCount)
	if err != nil {
		return Response{}, err
	}
	return toResponse(saved), nil
}

func (s *Service) List(ctx context.Context, userID string) ([]Response, error) {
	rows, err := s.repo.List(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]Response, 0, len(rows))
	for _, r := range rows {
		out = append(out, toResponse(r))
	}
	return out, nil
}

func (s *Service) Delete(ctx context.Context, userID, id string) error {
	return s.repo.Delete(ctx, userID, id)
}

func toResponse(s SavedSearch) Response {
	return Response{
		ID:          s.ID,
		Name:        s.Name,
		Filters:     s.Filters,
		ResultCount: s.ResultCount,
		CreatedAt:   s.CreatedAt.Format(time.RFC3339),
	}
}
