// Package demo backs the free "hook" swipe deck every user sees right
// after onboarding: the fixed pool of 10 male + 10 female is_demo=true
// profiles (see internal/profiles and cmd/seed), shown once so the
// interested/rejected swipe habit forms before the ₹1 unlock paywall
// (internal/unlock) gates everything real.
package demo

import (
	"context"
	"errors"
	"time"

	"matrimony-backend/internal/profiles"
)

// deckSize matches the "10 male + 10 female" pool this endpoint pulls
// against — set higher than 10 as a safety margin in case more than 10 of
// a gender ever get marked is_demo (e.g. a bigger seed run), so this
// always returns the full pool rather than silently truncating it.
const deckSize = 50

var ErrProfileRequired = errors.New("complete your profile before viewing the demo deck")

type Service struct {
	profilesRepo *profiles.Repository
}

func NewService(profilesRepo *profiles.Repository) *Service {
	return &Service{profilesRepo: profilesRepo}
}

// SwipeDeck returns every demo profile of the caller's opposite gender.
// requestedGender is the fallback source of truth for that when there's
// no profiles row yet at all — the demo deck sits right after the
// name/gender step (before the rest of onboarding creates the profile),
// so GetByUserID 404s on literally every first call; the client already
// knows the gender the user just picked one screen ago, so it passes it
// along here rather than this endpoint guessing "both genders" and
// showing a male member cards to a male caller. Once a real profiles row
// exists (post-onboarding), that row's own gender always wins over
// whatever the client sends, so a stale/forged query param can't matter.
//
// Only if NEITHER the profile row NOR requestedGender is available does
// this fall back to the full demo pool (both genders) — better than
// erroring outright (that used to hard-fail with ErrProfileRequired,
// sending every new signup straight to the ₹1 unlock paywall with an
// empty deck instead of ever showing the free hook swipe deck).
func (s *Service) SwipeDeck(ctx context.Context, userID string, requestedGender *string) ([]SwipeDeckCard, error) {
	var ownGender *string
	own, err := s.profilesRepo.GetByUserID(ctx, userID)
	switch {
	case errors.Is(err, profiles.ErrNotFound):
		ownGender = normalizeGender(requestedGender)
	case err != nil:
		return nil, err
	default:
		ownGender = own.Gender
	}

	opposing := opposite(ownGender)

	demoProfiles, err := s.profilesRepo.ListDemoProfiles(ctx, opposing, deckSize)
	if err != nil {
		return nil, err
	}

	out := make([]SwipeDeckCard, 0, len(demoProfiles))
	for _, p := range demoProfiles {
		photos, err := s.profilesRepo.ListPhotos(ctx, p.ID)
		if err != nil {
			return nil, err
		}
		var photoURL *string
		if len(photos) > 0 {
			url := photos[0].URL
			photoURL = &url
		}

		out = append(out, SwipeDeckCard{
			ProfileID:     p.ID,
			FullName:      p.FullName,
			City:          p.City,
			State:         p.State,
			MotherTongue:  p.MotherTongue,
			Religion:      p.Religion,
			PhotoURL:      photoURL,
			Age:           ageFromDOB(p.DateOfBirth),
			HeightCM:      p.HeightCM,
			MaritalStatus: p.MaritalStatus,
			Education:     p.Education,
			Occupation:    p.Occupation,
			Diet:          p.Diet,
			IsDemo:        true,
		})
	}
	return out, nil
}

func ageFromDOB(dob *time.Time) *int {
	if dob == nil {
		return nil
	}
	years := int(time.Since(*dob).Hours() / 24 / 365.25)
	return &years
}

// normalizeGender rejects anything but the two values profiles.gender
// actually stores — an unrecognized or garbage query param (rather than
// silently misinterpreting it) falls back to nil, the same as not
// sending one at all.
func normalizeGender(gender *string) *string {
	if gender == nil {
		return nil
	}
	switch *gender {
	case "male", "female":
		return gender
	default:
		return nil
	}
}

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
