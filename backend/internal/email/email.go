// Package email sends transactional emails (OTP codes, alerts). Only a
// console/mock sender is implemented for now; swap Sender for an SES/SMTP
// backed implementation when a real provider is wired up.
package email

import (
	"context"
	"log/slog"
)

type Sender interface {
	Send(ctx context.Context, toEmail, subject, body string) error
}

// ConsoleSender logs the message instead of sending it — used for local
// dev and tests so the OTP flow can be exercised without a real provider.
type ConsoleSender struct {
	Log *slog.Logger
}

func NewConsoleSender(log *slog.Logger) *ConsoleSender {
	return &ConsoleSender{Log: log}
}

func (s *ConsoleSender) Send(_ context.Context, toEmail, subject, body string) error {
	s.Log.Info("email (mock)", "to", toEmail, "subject", subject, "body", body)
	return nil
}
