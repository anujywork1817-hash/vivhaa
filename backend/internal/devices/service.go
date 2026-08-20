package devices

import (
	"context"
	"errors"
	"strings"
)

var (
	ErrTokenRequired    = errors.New("device token is required")
	ErrInvalidPlatform  = errors.New("platform must be android, ios or web")
)

var validPlatforms = map[string]bool{"android": true, "ios": true, "web": true}

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

// normalise validates and canonicalises client input before it reaches
// the database: tokens arrive with stray whitespace from mobile SDKs, and
// platform casing varies by client. Kept separate from [Register] so the
// rules are testable without a database.
func (s *Service) normalise(token, platform string) (string, string, error) {
	token = strings.TrimSpace(token)
	if token == "" {
		return "", "", ErrTokenRequired
	}

	if strings.TrimSpace(platform) == "" {
		platform = "android"
	}
	platform = strings.ToLower(strings.TrimSpace(platform))
	if !validPlatforms[platform] {
		return "", "", ErrInvalidPlatform
	}

	return token, platform, nil
}

func (s *Service) Register(ctx context.Context, userID, token, platform string) error {
	token, platform, err := s.normalise(token, platform)
	if err != nil {
		return err
	}
	return s.repo.Register(ctx, userID, token, platform)
}

func (s *Service) Unregister(ctx context.Context, userID, token string) error {
	token = strings.TrimSpace(token)
	if token == "" {
		return ErrTokenRequired
	}
	return s.repo.Unregister(ctx, userID, token)
}
