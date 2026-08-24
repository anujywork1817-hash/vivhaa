// Package firebase sends push notifications via Firebase Cloud Messaging.
// Only a console/mock sender is implemented for now — swap Sender for a
// real FCM-backed implementation when credentials are available.
package firebase

import (
	"context"
	"log/slog"
)

type Sender interface {
	// data rides alongside the visible notification as the FCM message's
	// data payload — the client reads it (RemoteMessage.data) to know
	// what a tapped notification is actually about (e.g. which chat
	// partner, which interest) so it can navigate there instead of just
	// opening to wherever the app happened to be.
	Send(ctx context.Context, userID, title, body string, data map[string]string) error

	// SendData delivers a data-only message: no notification block, so
	// the OS never auto-draws anything and doesn't wake the app for it —
	// for clients that need to build their own notification UI rather
	// than accept whatever generic banner the OS would draw.
	SendData(ctx context.Context, userID string, data map[string]string) error
}

// ConsoleSender logs the push instead of sending it — used for local dev
// so the notification-dispatch flow can be exercised without real FCM
// credentials.
type ConsoleSender struct {
	Log *slog.Logger
}

func NewConsoleSender(log *slog.Logger) *ConsoleSender {
	return &ConsoleSender{Log: log}
}

func (s *ConsoleSender) Send(_ context.Context, userID, title, body string, data map[string]string) error {
	s.Log.Info("push (mock)", "user_id", userID, "title", title, "body", body, "data", data)
	return nil
}

func (s *ConsoleSender) SendData(_ context.Context, userID string, data map[string]string) error {
	s.Log.Info("push data (mock)", "user_id", userID, "data", data)
	return nil
}
