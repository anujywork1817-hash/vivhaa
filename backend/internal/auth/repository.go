package auth

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("not found")

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) CreateUser(ctx context.Context, phone, email, passwordHash *string) (User, error) {
	const q = `
		INSERT INTO users (phone, email, password_hash)
		VALUES ($1, $2, $3)
		RETURNING id, phone, email, password_hash, phone_verified, email_verified, status, role, created_at`
	return r.scanUser(r.db.QueryRow(ctx, q, phone, email, passwordHash))
}

func (r *Repository) UpdateUserPassword(ctx context.Context, id string, passwordHash *string) error {
	const q = `UPDATE users SET password_hash = $2, updated_at = now() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id, passwordHash)
	return err
}

func (r *Repository) GetUserByIdentifier(ctx context.Context, identifier string) (User, error) {
	const q = `
		SELECT id, phone, email, password_hash, phone_verified, email_verified, status, role, created_at
		FROM users WHERE (phone = $1 OR email = $1) AND deleted_at IS NULL`
	return r.scanUser(r.db.QueryRow(ctx, q, identifier))
}

func (r *Repository) GetUserByID(ctx context.Context, id string) (User, error) {
	const q = `
		SELECT id, phone, email, password_hash, phone_verified, email_verified, status, role, created_at
		FROM users WHERE id = $1 AND deleted_at IS NULL`
	return r.scanUser(r.db.QueryRow(ctx, q, id))
}

func (r *Repository) scanUser(row pgx.Row) (User, error) {
	var u User
	err := row.Scan(&u.ID, &u.Phone, &u.Email, &u.PasswordHash, &u.PhoneVerified, &u.EmailVerified, &u.Status, &u.Role, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrNotFound
	}
	return u, err
}

// MarkVerified flips the verified flag for the given channel and activates
// the account — except a suspended account stays suspended. Callers (see
// Service.VerifyOTP) are expected to already reject a suspended account
// before ever reaching this, but the WHERE clause itself refuses to move
// status back to 'active' as a side effect, so this can't reactivate a
// suspended user even if some future call site forgets that check.
func (r *Repository) MarkVerified(ctx context.Context, userID, channel string) error {
	column := "phone_verified"
	if channel == "email" {
		column = "email_verified"
	}
	q := `UPDATE users SET ` + column + ` = TRUE, status = 'active', updated_at = now() WHERE id = $1 AND status <> 'suspended'`
	_, err := r.db.Exec(ctx, q, userID)
	return err
}

// LinkPhone attaches a phone number to an existing account that has none
// (Google/email signup never sets one) once its OTP has been verified.
// The DB's UNIQUE constraint on phone is the final backstop against a
// race with another account claiming the same number between the
// caller's own pre-check and this UPDATE.
func (r *Repository) LinkPhone(ctx context.Context, userID, phone string) error {
	const q = `UPDATE users SET phone = $2, phone_verified = TRUE, updated_at = now() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, userID, phone)
	return err
}

func (r *Repository) UpdateLastLogin(ctx context.Context, userID string) error {
	const q = `UPDATE users SET last_login_at = now() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, userID)
	return err
}

// CreateOTP invalidates any still-active codes for this identifier (any
// purpose) before issuing a new one. Without this, multiple valid codes
// could coexist — GetActiveOTP*'s "newest wins" lookup means the old ones
// stay live and independently guessable, and since each new row starts
// its own attempts counter at 0, an attacker locked out of one code (5
// wrong guesses) could just request a fresh one and get 5 more attempts,
// indefinitely — the lockout in VerifyOTP never actually caps total
// guesses across a burst of OTP requests. Scoped to the identifier, not
// identifier+purpose, since GetActiveOTPAnyPurpose picks the newest
// active row regardless of purpose too — an old signup OTP left dangling
// while a new login OTP is active is the same "multiple valid codes"
// hole under a different purpose.
func (r *Repository) CreateOTP(ctx context.Context, identifier, channel, purpose, codeHash string, expiresAt time.Time) (OTP, error) {
	const invalidate = `
		UPDATE otp_codes SET consumed_at = now()
		WHERE identifier = $1 AND consumed_at IS NULL AND expires_at > now()`
	if _, err := r.db.Exec(ctx, invalidate, identifier); err != nil {
		return OTP{}, err
	}

	const q = `
		INSERT INTO otp_codes (identifier, channel, purpose, code_hash, expires_at)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, identifier, channel, purpose, code_hash, attempts, max_attempts, expires_at, consumed_at`
	var o OTP
	err := r.db.QueryRow(ctx, q, identifier, channel, purpose, codeHash, expiresAt).Scan(
		&o.ID, &o.Identifier, &o.Channel, &o.Purpose, &o.CodeHash, &o.Attempts, &o.MaxAttempts, &o.ExpiresAt, &o.ConsumedAt)
	return o, err
}

// GetActiveOTP returns the most recent unexpired, unconsumed OTP for the
// given identifier/purpose pair.
func (r *Repository) GetActiveOTP(ctx context.Context, identifier, purpose string) (OTP, error) {
	const q = `
		SELECT id, identifier, channel, purpose, code_hash, attempts, max_attempts, expires_at, consumed_at
		FROM otp_codes
		WHERE identifier = $1 AND purpose = $2 AND consumed_at IS NULL AND expires_at > now()
		ORDER BY created_at DESC LIMIT 1`
	var o OTP
	err := r.db.QueryRow(ctx, q, identifier, purpose).Scan(
		&o.ID, &o.Identifier, &o.Channel, &o.Purpose, &o.CodeHash, &o.Attempts, &o.MaxAttempts, &o.ExpiresAt, &o.ConsumedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return OTP{}, ErrNotFound
	}
	return o, err
}

// GetActiveOTPAnyPurpose is like GetActiveOTP but doesn't filter by
// purpose — used when the caller (a passwordless client) has no way to
// know what purpose the OTP it's verifying was issued for.
func (r *Repository) GetActiveOTPAnyPurpose(ctx context.Context, identifier string) (OTP, error) {
	const q = `
		SELECT id, identifier, channel, purpose, code_hash, attempts, max_attempts, expires_at, consumed_at
		FROM otp_codes
		WHERE identifier = $1 AND consumed_at IS NULL AND expires_at > now()
		ORDER BY created_at DESC LIMIT 1`
	var o OTP
	err := r.db.QueryRow(ctx, q, identifier).Scan(
		&o.ID, &o.Identifier, &o.Channel, &o.Purpose, &o.CodeHash, &o.Attempts, &o.MaxAttempts, &o.ExpiresAt, &o.ConsumedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return OTP{}, ErrNotFound
	}
	return o, err
}

func (r *Repository) IncrementOTPAttempts(ctx context.Context, id string) error {
	const q = `UPDATE otp_codes SET attempts = attempts + 1 WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	return err
}

func (r *Repository) ConsumeOTP(ctx context.Context, id string) error {
	const q = `UPDATE otp_codes SET consumed_at = now() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	return err
}

func (r *Repository) CreateRefreshToken(ctx context.Context, userID, tokenHash string, expiresAt time.Time, userAgent, ip string) error {
	const q = `
		INSERT INTO refresh_tokens (user_id, token_hash, expires_at, user_agent, ip_address)
		VALUES ($1, $2, $3, $4, $5)`
	_, err := r.db.Exec(ctx, q, userID, tokenHash, expiresAt, userAgent, ip)
	return err
}

func (r *Repository) GetRefreshToken(ctx context.Context, tokenHash string) (RefreshToken, error) {
	const q = `
		SELECT id, user_id, token_hash, expires_at, revoked_at
		FROM refresh_tokens
		WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now()`
	var rt RefreshToken
	err := r.db.QueryRow(ctx, q, tokenHash).Scan(&rt.ID, &rt.UserID, &rt.TokenHash, &rt.ExpiresAt, &rt.RevokedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return RefreshToken{}, ErrNotFound
	}
	return rt, err
}

func (r *Repository) RevokeRefreshToken(ctx context.Context, tokenHash string) error {
	const q = `UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1 AND revoked_at IS NULL`
	_, err := r.db.Exec(ctx, q, tokenHash)
	return err
}

// RevokeRefreshTokenForUser scopes the revoke to a specific user so one
// user's access token can't be used to revoke another user's session.
func (r *Repository) RevokeRefreshTokenForUser(ctx context.Context, userID, tokenHash string) error {
	const q = `UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1 AND user_id = $2 AND revoked_at IS NULL`
	_, err := r.db.Exec(ctx, q, tokenHash, userID)
	return err
}
