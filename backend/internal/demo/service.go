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

// SwipeDeck returns every demo profile of the caller's opposite gender —
// or the full demo pool (both genders) if the caller's own gender isn't
// known yet, which keeps this endpoint usable immediately after
// onboarding regardless of exactly when the profile row lands.
func (s *Service) SwipeDeck(ctx context.Context, userID string) ([]SwipeDeckCard, error) {
	own, err := s.profilesRepo.GetByUserID(ctx, userID)
	if errors.Is(err, profiles.ErrNotFound) {
		return nil, ErrProfileRequired
	}
	if err != nil {
		return nil, err
	}

	opposing := opposite(own.Gender)

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
