package chat

import (
	"context"
	"time"

	"matrimony-backend/internal/chatguard"
)

// moderation_gate.go is the single enforcement point SendMessage calls
// before persisting a plain-text message. It:
//  1. Rejects immediately if the sender is currently under a temporary
//     restriction from prior violations.
//  2. Runs the message through chatguard.Engine.
//  3. On a block, logs the event, increments+escalates the sender's
//     violation count, and returns the generic ErrContactInfoBlocked —
//     never persisting the message.
//
// This is deliberately synchronous and lightweight (Phase 20): the
// detectors in chatguard are pure string/regex work with no I/O, so the
// added latency per send is microseconds, not a network round trip.
func (s *Service) enforceModeration(ctx context.Context, senderID, receiverID, body string) error {
	restriction, err := s.repo.GetRestriction(ctx, senderID)
	if err != nil {
		return err
	}
	if restriction.IsRestricted(time.Now()) {
		return ErrChatRestricted
	}

	result := s.guard.ModerateText(body)
	if result.Decision == chatguard.Allow {
		return nil
	}

	// Log first (observability must never be skipped just because the
	// violation-count write below fails), then escalate.
	_ = s.repo.LogModerationEvent(ctx, senderID, &receiverID, nil, string(result.Category), string(result.Decision))

	count, err := s.repo.RecordViolation(ctx, senderID)
	if err == nil {
		s.applyEscalation(ctx, senderID, count)
	}

	return ErrContactInfoBlocked
}

// applyEscalation maps a violation count to Phase 14's escalating
// response: nothing extra at low counts (the block itself is the
// "warning"), a temporary send restriction once RestrictThreshold is
// crossed, and a standing admin-review flag once ReviewThreshold is
// crossed — persistent abuse is surfaced to a human, never auto-banned.
func (s *Service) applyEscalation(ctx context.Context, userID string, violationCount int) {
	var until *time.Time
	if s.abuseCfg.RestrictThreshold > 0 && violationCount >= s.abuseCfg.RestrictThreshold {
		t := time.Now().Add(s.abuseCfg.RestrictDuration)
		until = &t
	}
	flagForReview := s.abuseCfg.ReviewThreshold > 0 && violationCount >= s.abuseCfg.ReviewThreshold
	if until != nil || flagForReview {
		_ = s.repo.ApplyRestriction(ctx, userID, until, flagForReview)
	}
}
