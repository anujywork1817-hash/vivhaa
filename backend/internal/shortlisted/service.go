package shortlisted

import (
	"context"
	"errors"
	"time"

	"matrimony-backend/internal/blocked"
	"matrimony-backend/internal/profiles"
)

var (
	ErrSelfShortlist = errors.New("cannot shortlist your own profile")
	ErrBlocked       = errors.New("you can't interact with this profile")
)

type Service struct {
	repo         *Repository
	profilesRepo *profiles.Repository
	blockedRepo  *blocked.Repository
}

func NewService(repo *Repository, profilesRepo *profiles.Repository, blockedRepo *blocked.Repository) *Service {
	return &Service{repo: repo, profilesRepo: profilesRepo, blockedRepo: blockedRepo}
}

func (s *Service) Add(ctx context.Context, userID, targetProfileID string) (Response, error) {
	targetProfile, err := s.profilesRepo.GetByID(ctx, targetProfileID)
	if errors.Is(err, profiles.ErrNotFound) {
		return Response{}, ErrNotFound
	}
	if err != nil {
		return Response{}, err
	}

	if targetProfile.UserID == userID {
		return Response{}, ErrSelfShortlist
	}

	isBlocked, err := s.blockedRepo.IsBlocked(ctx, userID, targetProfile.UserID)
	if err != nil {
		return Response{}, err
	}
	if isBlocked {
		return Response{}, ErrBlocked
	}

	sl, err := s.repo.Create(ctx, userID, targetProfile.UserID)
	if err != nil {
		return Response{}, err
	}
	return Response{ID: sl.ID, UserID: sl.UserID, TargetUserID: sl.TargetUserID, CreatedAt: sl.CreatedAt.Format(time.RFC3339)}, nil
}

func (s *Service) Remove(ctx context.Context, userID, targetProfileID string) error {
	targetProfile, err := s.profilesRepo.GetByID(ctx, targetProfileID)
	if errors.Is(err, profiles.ErrNotFound) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	return s.repo.Delete(ctx, userID, targetProfile.UserID)
}

func (s *Service) List(ctx context.Context, userID string) ([]Response, error) {
	rows, err := s.repo.List(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]Response, 0, len(rows))
	for _, r := range rows {
		out = append(out, Response{
			ID: r.ID, UserID: r.UserID, TargetUserID: r.TargetUserID, CreatedAt: r.CreatedAt.Format(time.RFC3339),
			ProfileID: r.ProfileID, FullName: r.FullName, City: r.City, PhotoURL: r.PhotoURL,
			Age: ageFromDOB(r.DateOfBirth), HeightCM: r.HeightCM, MaritalStatus: r.MaritalStatus,
			Religion: r.Religion, Education: r.Education, Occupation: r.Occupation, Diet: r.Diet, Manglik: r.Manglik,
		})
	}
	return out, nil
}
