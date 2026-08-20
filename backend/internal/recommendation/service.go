package recommendation

import (
	"context"
	"encoding/json"
	"errors"
	"hash/fnv"
	"sort"
	"time"

	"github.com/redis/go-redis/v9"

	"matrimony-backend/internal/matchmaking"
	"matrimony-backend/internal/preferences"
	"matrimony-backend/internal/profiles"
)

var ErrProfileRequired = errors.New("complete your profile before viewing matches")

// ErrLocationRequired is returned by GetNearby when the caller hasn't
// shared their own GPS location yet — there's no "near" without a "from".
var ErrLocationRequired = errors.New("share your location before viewing nearby matches")

const (
	recommendedPoolSize   = 200
	recommendedLimit      = 20
	dailyLimit            = 5
	dailyCacheTTL         = 25 * time.Hour
	nearbyDefaultRadiusKM = 50.0
	nearbyMaxRadiusKM     = 500.0
	nearbyLimit           = 50
)

type Service struct {
	matchRepo    *matchmaking.Repository
	profilesRepo *profiles.Repository
	prefsRepo    *preferences.Repository
	redisClient  *redis.Client
}

func NewService(matchRepo *matchmaking.Repository, profilesRepo *profiles.Repository, prefsRepo *preferences.Repository, redisClient *redis.Client) *Service {
	return &Service{matchRepo: matchRepo, profilesRepo: profilesRepo, prefsRepo: prefsRepo, redisClient: redisClient}
}

type scoredCandidate struct {
	candidate matchmaking.Candidate
	score     int
}

func (s *Service) scoredPool(ctx context.Context, userID string) ([]scoredCandidate, error) {
	ownProfile, err := s.profilesRepo.GetByUserID(ctx, userID)
	if errors.Is(err, profiles.ErrNotFound) {
		return nil, ErrProfileRequired
	}
	if err != nil {
		return nil, err
	}

	opposingGender := opposite(ownProfile.Gender)

	prefs, prefErr := s.prefsRepo.GetByUserID(ctx, userID)
	hasPrefs := prefErr == nil

	pool, err := s.matchRepo.CandidatePool(ctx, userID, opposingGender, recommendedPoolSize)
	if err != nil {
		return nil, err
	}

	scored := make([]scoredCandidate, 0, len(pool))
	for _, c := range pool {
		scored = append(scored, scoredCandidate{candidate: c, score: matchmaking.Score(prefs, hasPrefs, c)})
	}
	return scored, nil
}

func (s *Service) GetRecommended(ctx context.Context, userID string) ([]MatchResponse, error) {
	scored, err := s.scoredPool(ctx, userID)
	if err != nil {
		return nil, err
	}

	sort.SliceStable(scored, func(i, j int) bool { return scored[i].score > scored[j].score })

	if len(scored) > recommendedLimit {
		scored = scored[:recommendedLimit]
	}
	return toResponses(scored), nil
}

// GetDaily returns a small, date-stable subset, backed by a Redis cache
// keyed per user per day. cmd/scheduler proactively warms this cache once
// a day for every active user (async/batch processing); a cache miss here
// (e.g. a new user, or scheduler hasn't run yet) falls back to computing
// and caching it live, so the endpoint always works.
func (s *Service) GetDaily(ctx context.Context, userID string) ([]MatchResponse, error) {
	today := time.Now().UTC().Format("2006-01-02")
	cacheKey := dailyCacheKey(userID, today)

	if cached, err := s.redisClient.Get(ctx, cacheKey).Result(); err == nil {
		var resp []MatchResponse
		if jsonErr := json.Unmarshal([]byte(cached), &resp); jsonErr == nil {
			return resp, nil
		}
	}

	resp, err := s.computeDaily(ctx, userID, today)
	if err != nil {
		return nil, err
	}

	if encoded, err := json.Marshal(resp); err == nil {
		_ = s.redisClient.Set(ctx, cacheKey, encoded, dailyCacheTTL).Err()
	}

	return resp, nil
}

func (s *Service) computeDaily(ctx context.Context, userID, today string) ([]MatchResponse, error) {
	scored, err := s.scoredPool(ctx, userID)
	if err != nil {
		return nil, err
	}

	sort.SliceStable(scored, func(i, j int) bool {
		if scored[i].score != scored[j].score {
			return scored[i].score > scored[j].score
		}
		return dailyHash(scored[i].candidate.ProfileID, today) < dailyHash(scored[j].candidate.ProfileID, today)
	})

	if len(scored) > dailyLimit {
		scored = scored[:dailyLimit]
	}
	return toResponses(scored), nil
}

// GetAll returns every scored candidate in the pool (unlike GetRecommended,
// which caps at recommendedLimit) — this backs the Matches screen's "All
// Matches" view.
func (s *Service) GetAll(ctx context.Context, userID string) ([]MatchResponse, error) {
	scored, err := s.scoredPool(ctx, userID)
	if err != nil {
		return nil, err
	}

	sort.SliceStable(scored, func(i, j int) bool { return scored[i].score > scored[j].score })
	return toResponses(scored), nil
}

// GetNearby returns public profiles that have shared their location within
// radiusKM of the caller's own shared location, nearest first. radiusKM <= 0
// falls back to nearbyDefaultRadiusKM; values above nearbyMaxRadiusKM are
// clamped.
func (s *Service) GetNearby(ctx context.Context, userID string, radiusKM float64) ([]NearbyMatchResponse, error) {
	ownProfile, err := s.profilesRepo.GetByUserID(ctx, userID)
	if errors.Is(err, profiles.ErrNotFound) {
		return nil, ErrProfileRequired
	}
	if err != nil {
		return nil, err
	}
	if ownProfile.Latitude == nil || ownProfile.Longitude == nil {
		return nil, ErrLocationRequired
	}

	if radiusKM <= 0 {
		radiusKM = nearbyDefaultRadiusKM
	}
	if radiusKM > nearbyMaxRadiusKM {
		radiusKM = nearbyMaxRadiusKM
	}

	opposingGender := opposite(ownProfile.Gender)

	nearby, err := s.matchRepo.NearbyCandidates(ctx, userID, *ownProfile.Latitude, *ownProfile.Longitude, radiusKM, opposingGender, nearbyLimit)
	if err != nil {
		return nil, err
	}

	out := make([]NearbyMatchResponse, 0, len(nearby))
	for _, n := range nearby {
		out = append(out, NearbyMatchResponse{
			MatchResponse: MatchResponse{
				ProfileID:     n.ProfileID,
				FullName:      n.FullName,
				City:          n.City,
				State:         n.State,
				MotherTongue:  n.MotherTongue,
				Religion:      n.Religion,
				PhotoURL:      n.PhotoURL,
				Age:           ageFromDOB(n.DateOfBirth),
				HeightCM:      n.HeightCM,
				MaritalStatus: n.MaritalStatus,
				Education:     n.Education,
				Occupation:    n.Occupation,
				Diet:          n.Diet,
				Manglik:       n.Manglik,
			},
			DistanceKM: n.DistanceKM,
		})
	}
	return out, nil
}

func dailyCacheKey(userID, date string) string {
	return "daily_matches:" + userID + ":" + date
}

func dailyHash(profileID, date string) uint32 {
	h := fnv.New32a()
	_, _ = h.Write([]byte(profileID + date))
	return h.Sum32()
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

func toResponses(scored []scoredCandidate) []MatchResponse {
	out := make([]MatchResponse, 0, len(scored))
	for _, sc := range scored {
		out = append(out, MatchResponse{
			ProfileID:          sc.candidate.ProfileID,
			FullName:           sc.candidate.FullName,
			City:               sc.candidate.City,
			State:              sc.candidate.State,
			MotherTongue:       sc.candidate.MotherTongue,
			Religion:           sc.candidate.Religion,
			PhotoURL:           sc.candidate.PhotoURL,
			CompatibilityScore: sc.score,
			Age:                ageFromDOB(sc.candidate.DateOfBirth),
			HeightCM:           sc.candidate.HeightCM,
			MaritalStatus:      sc.candidate.MaritalStatus,
			Education:          sc.candidate.Education,
			Occupation:         sc.candidate.Occupation,
			Diet:               sc.candidate.Diet,
			Manglik:            sc.candidate.Manglik,
		})
	}
	return out
}
