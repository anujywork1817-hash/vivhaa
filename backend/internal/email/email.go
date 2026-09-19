// Package email sends transactional emails (OTP codes, alerts). ConsoleSender
// remains for local dev/tests; SMTPSender is the real provider, used
// whenever SMTP_HOST etc. are configured (see configs.EmailConfig).
package email

import (
	"context"
	"crypto/tls"
	"fmt"
	"log/slog"
	"net"
	"net/smtp"
	"strings"
	"time"
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

// SMTPSender sends real mail through an SMTP relay (Gmail, Zoho, a
// transactional provider's SMTP endpoint, an internal relay — anything
// speaking standard SMTP+AUTH). Host/Port/Username/Password/From come from
// configs.EmailConfig; FromName is optional cosmetic display text.
type SMTPSender struct {
	Host     string
	Port     string
	Username string
	Password string
	From     string
	FromName string
}

func NewSMTPSender(host, port, username, password, from, fromName string) *SMTPSender {
	return &SMTPSender{
		Host:     host,
		Port:     port,
		Username: username,
		Password: password,
		From:     from,
		FromName: fromName,
	}
}

// Send dials the configured relay and delivers a plain-text message.
// Port 465 is implicit TLS (dial straight into TLS, then talk SMTP inside
// it — smtp.SendMail can't do this, it only knows STARTTLS); anything else
// (587, 25, ...) goes through smtp.SendMail, which negotiates STARTTLS
// itself when the server advertises it.
//
// ctx isn't threaded into net/smtp's calls (the stdlib package predates
// context and offers no hook for one) — the dial/write timeouts below are
// this method's own bound instead, so a hung relay can't block a request
// indefinitely.
func (s *SMTPSender) Send(ctx context.Context, toEmail, subject, body string) error {
	addr := net.JoinHostPort(s.Host, s.Port)
	auth := smtp.PlainAuth("", s.Username, s.Password, s.Host)
	msg := s.buildMessage(toEmail, subject, body)

	if s.Port == "465" {
		return s.sendImplicitTLS(addr, auth, toEmail, msg)
	}

	done := make(chan error, 1)
	go func() { done <- smtp.SendMail(addr, auth, s.From, []string{toEmail}, msg) }()
	select {
	case err := <-done:
		return err
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (s *SMTPSender) sendImplicitTLS(addr string, auth smtp.Auth, toEmail string, msg []byte) error {
	dialer := &net.Dialer{Timeout: 10 * time.Second}
	conn, err := tls.DialWithDialer(dialer, "tcp", addr, &tls.Config{ServerName: s.Host})
	if err != nil {
		return fmt.Errorf("email: dial %s: %w", addr, err)
	}
	client, err := smtp.NewClient(conn, s.Host)
	if err != nil {
		return fmt.Errorf("email: smtp handshake: %w", err)
	}
	defer client.Close()

	if err := client.Auth(auth); err != nil {
		return fmt.Errorf("email: auth: %w", err)
	}
	if err := client.Mail(s.From); err != nil {
		return err
	}
	if err := client.Rcpt(toEmail); err != nil {
		return err
	}
	w, err := client.Data()
	if err != nil {
		return err
	}
	if _, err := w.Write(msg); err != nil {
		return err
	}
	if err := w.Close(); err != nil {
		return err
	}
	return client.Quit()
}

func (s *SMTPSender) buildMessage(toEmail, subject, body string) []byte {
	from := s.From
	if s.FromName != "" {
		from = fmt.Sprintf("%s <%s>", s.FromName, s.From)
	}
	var b strings.Builder
	b.WriteString("From: " + from + "\r\n")
	b.WriteString("To: " + toEmail + "\r\n")
	b.WriteString("Subject: " + subject + "\r\n")
	b.WriteString("MIME-Version: 1.0\r\n")
	b.WriteString("Content-Type: text/plain; charset=\"UTF-8\"\r\n")
	b.WriteString("\r\n")
	b.WriteString(body)
	return []byte(b.String())
}
