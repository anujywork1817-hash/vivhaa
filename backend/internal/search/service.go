package search

import (
	"context"
	"errors"

	"matrimony-backend/internal/blocked"
	"matrimony-backend/internal/profiles"
)

const (
	defaultLimit = 20
	maxLimit     = 100
)

type Service struct {
	repo         *Repository
	blockedRepo  *blocked.Repository
	profilesRepo *profiles.Repository
}

func NewService(repo *Repository, blockedRepo *blocked.Repository, profilesRepo *profiles.Repository) *Service {
	return &Service{repo: repo, blockedRepo: blockedRepo, profilesRepo: profilesRepo}
}

func (s *Service) Search(ctx context.Context, userID string, q Query) ([]ProfileResult, Meta, error) {
	if q.Page < 1 {
		q.Page = 1
	}
	if q.Limit < 1 {
		q.Limit = defaultLimit
	}
	if q.Limit > maxLimit {
		q.Limit = maxLimit
	}

	// A matrimony search is opposite-gender by nature — default to it from
	// the caller's own profile whenever they haven't explicitly asked for
	// a specific gender, so every entry point into search (not just the
	// advanced-filters screen where a client might set this) is
	// automatically restricted. Without this, a client that never sends
	// `gender` (e.g. the "New Members" list, which just hits this endpoint
	// with a limit) showed both genders to everyone.
	if q.Gender == nil {
		ownProfile, err := s.profilesRepo.GetByUserID(ctx, userID)
		switch {
		case errors.Is(err, profiles.ErrNotFound):
			// A caller who hasn't created a profile yet (still mid-
			// onboarding, or an admin/test account) is an expected, common
			// state, not a failure — there's nothing to default the gender
			// filter to here, same as an existing profile with gender
			// unset (see opposite()). Only a genuine lookup error below
			// fails closed.
		case err != nil:
			// Fail closed, not open: silently proceeding unfiltered on a
			// transient DB error here would resurrect the exact bug this
			// default gender filter exists to fix (both genders shown to
			// everyone) — better to fail the request than to fail the
			// safety filter.
			return nil, Meta{}, err
		default:
			q.Gender = opposite(ownProfile.Gender)
		}
	}

	blockedIDs, err := s.blockedRepo.ListBlockedUserIDs(ctx, userID)
	if err != nil {
		return nil, Meta{}, err
	}
	excludeUserIDs := append([]string{userID}, blockedIDs...)

	results, total, err := s.repo.Search(ctx, excludeUserIDs, q)
	if err != nil {
		return nil, Meta{}, err
	}
	if results == nil {
		results = []ProfileResult{}
	}

	return results, Meta{Page: q.Page, Limit: q.Limit, Total: total}, nil
}

// opposite maps a profile's own gender to the gender search/matches should
// default to showing. Unknown/unset genders default to no filter (nil) —
// there's nothing correct to assume for a profile whose own gender isn't
// known yet.
func opposite(gender *string) *string {
	if gender == nil {
		return nil
	}
	var o string
	switch *gender {
	case "male":
		o = "female"
	case "female":
		o = "male"
	default:
		return nil
	}
	return &o
}
