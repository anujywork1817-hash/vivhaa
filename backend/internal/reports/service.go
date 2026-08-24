package reports

import (
	"context"
	"errors"
	"strings"
	"time"

	"matrimony-backend/internal/profiles"
)

var (
	ErrSelfReport    = errors.New("cannot report your own profile")
	ErrNotFound      = errors.New("not found")
	ErrInvalidReason = errors.New("unrecognized report reason")
	// ErrCustomReasonNeedsDetails guards the "other" (custom) reason —
	// picking it with no explanation gives an admin nothing to act on.
	ErrCustomReasonNeedsDetails = errors.New("please describe the issue for a custom report")
)

type Service struct {
	repo         *Repository
	profilesRepo *profiles.Repository
}

func NewService(repo *Repository, profilesRepo *profiles.Repository) *Service {
	return &Service{repo: repo, profilesRepo: profilesRepo}
}

func (s *Service) Submit(ctx context.Context, reporterUserID, targetProfileID string, req ReportRequest) (Response, error) {
	targetProfile, err := s.profilesRepo.GetByID(ctx, targetProfileID)
	if errors.Is(err, profiles.ErrNotFound) {
		return Response{}, ErrNotFound
	}
	if err != nil {
		return Response{}, err
	}

	if targetProfile.UserID == reporterUserID {
		return Response{}, ErrSelfReport
	}

	category, priority, _, ok := ReasonMeta(req.Reason)
	if !ok {
		return Response{}, ErrInvalidReason
	}
	if req.Reason == "other" && (req.Details == nil || strings.TrimSpace(*req.Details) == "") {
		return Response{}, ErrCustomReasonNeedsDetails
	}

	rep, err := s.repo.Create(ctx, reporterUserID, targetProfile.UserID, req.Reason, req.Details, category, priority)
	if err != nil {
		return Response{}, err
	}

	return toResponse(rep), nil
}

func toResponse(r Report) Response {
	return Response{
		ID:             r.ID,
		ReporterUserID: r.ReporterUserID,
		ReportedUserID: r.ReportedUserID,
		Reason:         r.Reason,
		Details:        r.Details,
		Category:       r.Category,
		Priority:       r.Priority,
		Status:         r.Status,
		CreatedAt:      r.CreatedAt.Format(time.RFC3339),
	}
}
