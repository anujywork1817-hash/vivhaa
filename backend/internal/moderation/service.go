package moderation

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

const (
	defaultLimit = 20
	maxLimit     = 100
)

func (s *Service) ListPending(ctx context.Context, page, limit int) ([]Response, ListMeta, error) {
	if page < 1 {
		page = 1
	}
	if limit < 1 {
		limit = defaultLimit
	}
	if limit > maxLimit {
		limit = maxLimit
	}

	total, err := s.repo.CountByStatus(ctx, "pending")
	if err != nil {
		return nil, ListMeta{}, err
	}

	rows, err := s.repo.ListByStatus(ctx, "pending", limit, (page-1)*limit)
	if err != nil {
		return nil, ListMeta{}, err
	}
	out := make([]Response, 0, len(rows))
	for _, r := range rows {
		out = append(out, toResponse(r))
	}
	return out, ListMeta{Page: page, Limit: limit, Total: total}, nil
}

func (s *Service) Resolve(ctx context.Context, id, reviewerID string, req ResolveRequest) (Response, error) {
	resolved, err := s.repo.Resolve(ctx, id, req.Status, reviewerID, req.Notes)
	if err != nil {
		return Response{}, err
	}

	if req.SuspendUser {
		if err := s.repo.SuspendUser(ctx, resolved.ReportedUserID); err != nil {
			return Response{}, err
		}
	}

	return toResponse(resolved), nil
}

func toResponse(r Report) Response {
	var reviewedAt *string
	if r.ReviewedAt != nil {
		s := r.ReviewedAt.Format(time.RFC3339)
		reviewedAt = &s
	}
	return Response{
		ID:             r.ID,
		ReporterUserID: r.ReporterUserID,
		ReportedUserID: r.ReportedUserID,
		Reason:         r.Reason,
		Details:        r.Details,
		Status:         r.Status,
		ReviewNotes:    r.ReviewNotes,
		CreatedAt:      r.CreatedAt.Format(time.RFC3339),
		ReviewedAt:     reviewedAt,
	}
}
