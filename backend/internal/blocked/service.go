package blocked

import (
	"context"
	"errors"
	"time"

	"matrimony-backend/internal/profiles"
)

var ErrSelfBlock = errors.New("cannot block your own profile")

type Service struct {
	repo         *Repository
	profilesRepo *profiles.Repository
}

func NewService(repo *Repository, profilesRepo *profiles.Repository) *Service {
	return &Service{repo: repo, profilesRepo: profilesRepo}
}

func (s *Service) Block(ctx context.Context, userID, targetProfileID string) (Response, error) {
	targetUserID, err := s.resolveTargetUserID(ctx, targetProfileID)
	if err != nil {
		return Response{}, err
	}

	if targetUserID == userID {
		return Response{}, ErrSelfBlock
	}

	b, err := s.repo.Create(ctx, userID, targetUserID)
	if err != nil {
		return Response{}, err
	}
	return Response{ID: b.ID, UserID: b.UserID, BlockedUserID: b.BlockedUserID, CreatedAt: b.CreatedAt.Format(time.RFC3339)}, nil
}

func (s *Service) Unblock(ctx context.Context, userID, targetProfileID string) error {
	targetUserID, err := s.resolveTargetUserID(ctx, targetProfileID)
	if err != nil {
		return err
	}
	return s.repo.Delete(ctx, userID, targetUserID)
}

// Status reports the block relationship between userID and targetProfileID
// in each direction — used by profile detail / chat to explain a locked
// action ("you blocked them" vs. "they blocked you") instead of a generic
// "you can't message this member" with no context.
func (s *Service) Status(ctx context.Context, userID, targetProfileID string) (StatusResponse, error) {
	targetUserID, err := s.resolveTargetUserID(ctx, targetProfileID)
	if err != nil {
		return StatusResponse{}, err
	}

	if targetUserID == userID {
		return StatusResponse{}, nil
	}

	blockedByMe, blockedMe, err := s.repo.Directions(ctx, userID, targetUserID)
	if err != nil {
		return StatusResponse{}, err
	}
	return StatusResponse{IsBlockedByMe: blockedByMe, HasBlockedMe: blockedMe}, nil
}

// resolveTargetUserID accepts either a profile ID (the normal case — every
// screen that has a "block" action reached it by loading a profile) or a
// user ID, falling back to the latter if the former doesn't resolve. The
// chat "More" menu derives its target's profile ID from a client-side
// user-ID -> profile-ID map that isn't always populated (e.g. the
// underlying interest was later withdrawn/deleted), which made block/
// unblock/status silently 404 from chat specifically whenever that
// mapping came up empty and fell back to a raw user ID. Both ID types are
// UUIDs from unrelated columns, so this fallback can't cross-match the
// wrong record.
func (s *Service) resolveTargetUserID(ctx context.Context, targetID string) (string, error) {
	if p, err := s.profilesRepo.GetByID(ctx, targetID); err == nil {
		return p.UserID, nil
	} else if !errors.Is(err, profiles.ErrNotFound) {
		return "", err
	}

	if p, err := s.profilesRepo.GetByUserID(ctx, targetID); err == nil {
		return p.UserID, nil
	} else if !errors.Is(err, profiles.ErrNotFound) {
		return "", err
	}

	return "", ErrNotFound
}

func (s *Service) List(ctx context.Context, userID string) ([]Response, error) {
	rows, err := s.repo.List(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]Response, 0, len(rows))
	for _, r := range rows {
		out = append(out, Response{
			ID: r.ID, UserID: r.UserID, BlockedUserID: r.BlockedUserID, CreatedAt: r.CreatedAt.Format(time.RFC3339),
			ProfileID: r.ProfileID, FullName: r.FullName, City: r.City, PhotoURL: r.PhotoURL,
		})
	}
	return out, nil
}
