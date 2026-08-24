package firebase

import (
	"context"
	"errors"
	"fmt"
	"log/slog"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

// TokenResolver maps a user to the push tokens of their signed-in devices.
// Implemented by internal/devices; kept as an interface here so this
// package stays free of any dependency on the rest of the app.
type TokenResolver interface {
	ListTokens(ctx context.Context, userID string) ([]string, error)
	DeleteTokens(ctx context.Context, tokens []string) error
}

// FCMSender delivers notifications through Firebase Cloud Messaging to
// every device a user has registered.
type FCMSender struct {
	client *messaging.Client
	tokens TokenResolver
	log    *slog.Logger
}

// NewFCMSender builds a sender from a Firebase service-account key, given
// either as inline JSON or a file path. projectID may be empty when the
// credentials already carry one.
func NewFCMSender(ctx context.Context, credentialsJSON, credentialsFile, projectID string, tokens TokenResolver, log *slog.Logger) (*FCMSender, error) {
	var opt option.ClientOption
	switch {
	case credentialsJSON != "":
		opt = option.WithCredentialsJSON([]byte(credentialsJSON))
	case credentialsFile != "":
		opt = option.WithCredentialsFile(credentialsFile)
	default:
		return nil, errors.New("no firebase credentials provided")
	}

	cfg := &firebase.Config{}
	if projectID != "" {
		cfg.ProjectID = projectID
	}

	app, err := firebase.NewApp(ctx, cfg, opt)
	if err != nil {
		return nil, fmt.Errorf("init firebase app: %w", err)
	}

	client, err := app.Messaging(ctx)
	if err != nil {
		return nil, fmt.Errorf("init fcm client: %w", err)
	}

	return &FCMSender{client: client, tokens: tokens, log: log}, nil
}

// Send pushes to all of the user's devices. A user with no registered
// devices is not an error — they simply aren't reachable by push (never
// opened the app on a device, or denied notification permission), and the
// in-app notification has already been persisted by the caller.
func (s *FCMSender) Send(ctx context.Context, userID, title, body string, data map[string]string) error {
	return s.send(ctx, userID, &messaging.MulticastMessage{
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
			Notification: &messaging.AndroidNotification{
				// Matches the channel the Flutter client creates; without
				// it Android 8+ drops the notification silently.
				ChannelID: "vivaha_default",
			},
		},
	})
}

// SendData delivers a data-only push (no Notification block), so the OS
// doesn't auto-draw anything and the app's background message handler is
// solely responsible for what the user sees — for clients that need a
// custom notification UI rather than a generic system banner.
func (s *FCMSender) SendData(ctx context.Context, userID string, data map[string]string) error {
	return s.send(ctx, userID, &messaging.MulticastMessage{
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
		},
	})
}

// send fills in Tokens from the user's registered devices and delivers
// msg, pruning any tokens FCM reports as permanently dead. A user with no
// devices is not an error — see the Send doc comment above.
func (s *FCMSender) send(ctx context.Context, userID string, msg *messaging.MulticastMessage) error {
	tokens, err := s.tokens.ListTokens(ctx, userID)
	if err != nil {
		return fmt.Errorf("look up device tokens: %w", err)
	}
	if len(tokens) == 0 {
		s.log.Debug("push skipped, no registered devices", "user_id", userID)
		return nil
	}
	msg.Tokens = tokens

	resp, err := s.client.SendEachForMulticast(ctx, msg)
	if err != nil {
		return fmt.Errorf("send push: %w", err)
	}

	s.pruneDeadTokens(ctx, tokens, resp)

	if resp.FailureCount > 0 {
		s.log.Warn("some pushes failed",
			"user_id", userID, "sent", resp.SuccessCount, "failed", resp.FailureCount)
	}
	return nil
}

// pruneDeadTokens deletes tokens FCM reports as permanently invalid.
// Without this they accumulate forever — every future notification would
// keep paying for send attempts that can never succeed, and the failure
// counts would hide genuine delivery problems.
func (s *FCMSender) pruneDeadTokens(ctx context.Context, tokens []string, resp *messaging.BatchResponse) {
	var dead []string
	for i, r := range resp.Responses {
		if r.Success || i >= len(tokens) {
			continue
		}
		// Only unregistered/invalid-argument mean the token itself is bad;
		// anything else (quota, transient server error) is worth retrying
		// with the same token later.
		if messaging.IsUnregistered(r.Error) || messaging.IsInvalidArgument(r.Error) {
			dead = append(dead, tokens[i])
		}
	}
	if len(dead) == 0 {
		return
	}
	if err := s.tokens.DeleteTokens(ctx, dead); err != nil {
		s.log.Warn("could not delete stale device tokens", "count", len(dead), "error", err)
		return
	}
	s.log.Info("removed stale device tokens", "count", len(dead))
}
