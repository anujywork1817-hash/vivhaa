package subscriptions

import (
	"context"
	"errors"
	"os"
	"time"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// gatingEnabled is a launch switch, not a plan setting: the app is meant
// to run fully free at first (everyone effectively on the premium
// feature set) until premium is ready to actually launch, at which point
// setting PREMIUM_GATING_ENABLED=true flips HasFeature back to real
// per-plan enforcement without any other code change. Plans, payments,
// and the admin subscription views are all unaffected either way — this
// only short-circuits the one method call sites use to gate a feature.
func gatingEnabled() bool {
	return os.Getenv("PREMIUM_GATING_ENABLED") == "true"
}

func (s *Service) ListPlans(ctx context.Context) ([]PlanResponse, error) {
	plans, err := s.repo.ListActivePlans(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]PlanResponse, 0, len(plans))
	for _, p := range plans {
		out = append(out, PlanResponse{Code: p.Code, Name: p.Name, PriceINR: p.PriceINR, DurationDays: p.DurationDays, Features: p.Features, TierRank: p.TierRank})
	}
	return out, nil
}

// GetMine returns the caller's current subscription state — their active
// plan if they have one, or the free plan otherwise.
func (s *Service) GetMine(ctx context.Context, userID string) (SubscriptionResponse, error) {
	sub, err := s.repo.GetActiveByUserID(ctx, userID)
	if errors.Is(err, ErrNotFound) {
		freePlan, err := s.repo.GetPlanByCode(ctx, "free")
		if err != nil {
			return SubscriptionResponse{}, err
		}
		return SubscriptionResponse{Status: "active", PlanCode: freePlan.Code}, nil
	}
	if err != nil {
		return SubscriptionResponse{}, err
	}

	plan, err := s.repo.GetPlanByID(ctx, sub.PlanID)
	if err != nil {
		return SubscriptionResponse{}, err
	}

	var startsAt, endsAt *string
	if sub.StartsAt != nil {
		v := sub.StartsAt.Format(time.RFC3339)
		startsAt = &v
	}
	if sub.EndsAt != nil {
		v := sub.EndsAt.Format(time.RFC3339)
		endsAt = &v
	}

	return SubscriptionResponse{Status: sub.Status, PlanCode: plan.Code, StartsAt: startsAt, EndsAt: endsAt}, nil
}

// HasFeature reports whether userID's current plan (active subscription,
// or the free plan if they have none) includes featureKey.
func (s *Service) HasFeature(ctx context.Context, userID, featureKey string) (bool, error) {
	if !gatingEnabled() {
		return true, nil
	}

	sub, err := s.repo.GetActiveByUserID(ctx, userID)
	if errors.Is(err, ErrNotFound) {
		freePlan, err := s.repo.GetPlanByCode(ctx, "free")
		if err != nil {
			return false, err
		}
		return freePlan.Features[featureKey], nil
	}
	if err != nil {
		return false, err
	}

	plan, err := s.repo.GetPlanByID(ctx, sub.PlanID)
	if err != nil {
		return false, err
	}
	return plan.Features[featureKey], nil
}
