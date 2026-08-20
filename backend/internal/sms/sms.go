// Package sms sends SMS messages (OTP codes, alerts). Only a console/mock
// sender is implemented for now; swap Sender for a Twilio/MSG91-backed
// implementation when a real provider is wired up.
package sms

import (
	"context"
	"log/slog"
)

type Sender interface {
	Send(ctx context.Context, toPhone, message string) error
}

// ConsoleSender logs the message instead of sending it — used for local
// dev and tests so the OTP flow can be exercised without a real provider.
type ConsoleSender struct {
	Log *slog.Logger
}

func NewConsoleSender(log *slog.Logger) *ConsoleSender {
	return &ConsoleSender{Log: log}
}

func (s *ConsoleSender) Send(_ context.Context, toPhone, message string) error {
	s.Log.Info("sms (mock)", "to", toPhone, "message", message)
	return nil
}
