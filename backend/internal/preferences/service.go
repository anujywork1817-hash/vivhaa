package preferences

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

func (s *Service) Upsert(ctx context.Context, userID string, req UpsertRequest) (Response, error) {
	p := Preferences{
		UserID:        userID,
		MinAge:        req.MinAge,
		MaxAge:        req.MaxAge,
		MinHeightCM:   req.MinHeightCM,
		MaxHeightCM:   req.MaxHeightCM,
		MaritalStatus: req.MaritalStatus,
		Religion:      req.Religion,
		Community:     req.Community,
		MotherTongue:  req.MotherTongue,
		Education:     req.Education,
		MinIncomeINR:  req.MinIncomeINR,
		Country:       req.Country,
		State:         req.State,
		City:          req.City,
		Diet:          req.Diet,

		Profession:       req.Profession,
		WorkingWith:      req.WorkingWith,
		ProfileManagedBy: req.ProfileManagedBy,

		AboutPartner: req.AboutPartner,
	}

	saved, err := s.repo.Upsert(ctx, p)
	if err != nil {
		return Response{}, err
	}
	return toResponse(saved), nil
}

func (s *Service) GetMine(ctx context.Context, userID string) (Response, error) {
	p, err := s.repo.GetByUserID(ctx, userID)
	if err != nil {
		return Response{}, err
	}
	return toResponse(p), nil
}

func toResponse(p Preferences) Response {
	return Response{
		ID:            p.ID,
		UserID:        p.UserID,
		MinAge:        p.MinAge,
		MaxAge:        p.MaxAge,
		MinHeightCM:   p.MinHeightCM,
		MaxHeightCM:   p.MaxHeightCM,
		MaritalStatus: p.MaritalStatus,
		Religion:      p.Religion,
		Community:     p.Community,
		MotherTongue:  p.MotherTongue,
		Education:     p.Education,
		MinIncomeINR:  p.MinIncomeINR,
		Country:       p.Country,
		State:         p.State,
		City:          p.City,
		Diet:          p.Diet,

		Profession:       p.Profession,
		WorkingWith:      p.WorkingWith,
		ProfileManagedBy: p.ProfileManagedBy,

		AboutPartner: p.AboutPartner,
		CreatedAt:     p.CreatedAt.Format(time.RFC3339),
		UpdatedAt:     p.UpdatedAt.Format(time.RFC3339),
	}
}
