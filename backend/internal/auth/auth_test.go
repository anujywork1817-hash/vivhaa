package auth

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sync/atomic"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"

	"matrimony-backend/internal/analytics"
	"matrimony-backend/internal/email"
	"matrimony-backend/internal/sms"
	"matrimony-backend/pkg/googleauth"
	"matrimony-backend/pkg/jwt"
	"matrimony-backend/pkg/ratelimit"
	"matrimony-backend/pkg/testdb"
)

// ---- pure-function unit tests (no DB, no network — same convention as
// internal/devices/service_test.go and internal/profiles/*_test.go) ----

func TestChannelFor(t *testing.T) {
	if id, ch := channelFor("+919876543210", ""); id != "+919876543210" || ch != "phone" {
		t.Errorf("channelFor(phone, \"\") = (%q, %q), want (+919876543210, phone)", id, ch)
	}
	if id, ch := channelFor("", "a@b.com"); id != "a@b.com" || ch != "email" {
		t.Errorf("channelFor(\"\", email) = (%q, %q), want (a@b.com, email)", id, ch)
	}
	// Phone takes priority when (incorrectly) both are supplied — matches
	// SignupRequest's validation, which never actually allows this, but
	// pins the tie-break behavior explicitly.
	if id, _ := channelFor("+91", "a@b.com"); id != "+91" {
		t.Errorf("channelFor with both set should prefer phone, got %q", id)
	}
}

func TestInferChannel(t *testing.T) {
	if inferChannel("a@b.com") != "email" {
		t.Error("inferChannel with '@' should return email")
	}
	if inferChannel("+919876543210") != "phone" {
		t.Error("inferChannel without '@' should return phone")
	}
}

func TestGenerateOTPCode(t *testing.T) {
	code, err := generateOTPCode()
	if err != nil {
		t.Fatalf("generateOTPCode() error: %v", err)
	}
	if len(code) != otpLength {
		t.Errorf("generateOTPCode() = %q, want length %d", code, otpLength)
	}
	for _, r := range code {
		if r < '0' || r > '9' {
			t.Errorf("generateOTPCode() = %q, contains non-digit", code)
			break
		}
	}
}

func TestHashOTP_CompareOTP(t *testing.T) {
	code := "123456"
	hash := hashOTP(code)

	if !compareOTP(code, hash) {
		t.Error("compareOTP should accept the code that produced the hash")
	}
	if compareOTP("654321", hash) {
		t.Error("compareOTP should reject a different code")
	}
	// hashOTP must not be the identity function / plaintext-comparable —
	// otherwise a DB read (e.g. a compromised backup) hands over live
	// codes directly instead of just their hashes.
	if hash == code {
		t.Error("hashOTP(code) should not equal the plaintext code")
	}
}

// ---- integration tests against a real Postgres (pkg/testdb) ----
// See pkg/testdb's doc comment for one-time setup. Every test here skips
// (not fails) if the test database isn't reachable.

var testPhoneSeq int64

// uniquePhone returns a syntactically valid, collision-free E.164 number
// for one test run — phone is UNIQUE in the schema, and tests run
// concurrently (t.Parallel isn't used here, but repeated `go test -run`
// invocations must not collide with rows a previous run's cleanup missed).
func uniquePhone(t *testing.T) string {
	t.Helper()
	n := atomic.AddInt64(&testPhoneSeq, 1)
	return fmt.Sprintf("+19255%06d%d", time.Now().Unix()%1000000, n%10)
}

func uniqueEmail(t *testing.T) string {
	t.Helper()
	n := atomic.AddInt64(&testPhoneSeq, 1)
	return fmt.Sprintf("google-auth-test-%d-%d@example.com", time.Now().UnixNano(), n)
}

func newTestService(t *testing.T) *Service {
	t.Helper()
	pool := testdb.Connect(t)

	mr := miniredis.RunT(t)
	redisClient := redis.NewClient(&redis.Options{Addr: mr.Addr(), Protocol: 2})
	t.Cleanup(func() { _ = redisClient.Close() })

	repo := NewRepository(pool)
	analyticsSvc := analytics.NewService(analytics.NewRepository(pool))
	issuer := jwt.NewIssuer("test-access-secret", time.Hour)
	limiter := ratelimit.New(redisClient)

	return NewService(
		repo,
		&sms.ConsoleSender{Log: slog.Default()},
		&email.ConsoleSender{Log: slog.Default()},
		issuer,
		30*24*time.Hour,
		true, // devMode — lets tests read the OTP back off the response
		analyticsSvc,
		googleauth.NewVerifier(nil),
		limiter,
	)
}

func TestSignup_CreatesPendingUserAndSendsOTP(t *testing.T) {
	svc := newTestService(t)
	phone := uniquePhone(t)
	ctx := context.Background()

	resp, err := svc.Signup(ctx, SignupRequest{Phone: phone, Password: "correct-horse-1"})
	if err != nil {
		t.Fatalf("Signup() error: %v", err)
	}
	if resp.Identifier != phone || resp.Channel != "phone" {
		t.Errorf("Signup() response = %+v, want identifier=%s channel=phone", resp, phone)
	}
	if resp.DevOTP == "" {
		t.Error("Signup() in devMode should echo the OTP back")
	}

	user, err := svc.repo.GetUserByIdentifier(ctx, phone)
	if err != nil {
		t.Fatalf("GetUserByIdentifier() error: %v", err)
	}
	if user.Status != "pending" {
		t.Errorf("new signup's status = %q, want pending", user.Status)
	}
	t.Cleanup(func() { _, _ = svc.repo.db.Exec(ctx, `DELETE FROM users WHERE id = $1`, user.ID) })
}

func TestSignup_AlreadyActiveAccount_ReturnsErrAlreadyRegistered(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()
	phone := uniquePhone(t)

	mustCreateActiveUser(t, ctx, svc.repo.db, phone, "some-password-1")

	_, err := svc.Signup(ctx, SignupRequest{Phone: phone, Password: "another-password-1"})
	if !errors.Is(err, ErrAlreadyRegistered) {
		t.Errorf("Signup() for an already-active identifier = %v, want ErrAlreadyRegistered", err)
	}
}

func TestLogin_WrongPassword_ReturnsErrInvalidCredentials(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()
	phone := uniquePhone(t)
	mustCreateActiveUser(t, ctx, svc.repo.db, phone, "the-real-password-1")

	_, err := svc.Login(ctx, LoginRequest{Identifier: phone, Password: "totally-wrong"}, "test-agent", "127.0.0.1")
	if !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("Login() with wrong password = %v, want ErrInvalidCredentials", err)
	}
}

func TestLogin_SuspendedAccount_ReturnsErrAccountSuspended(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()
	phone := uniquePhone(t)
	mustCreateActiveUser(t, ctx, svc.repo.db, phone, "the-real-password-1")

	// Mirrors admin.Repository.UpdateUserStatus without importing
	// internal/admin — same effect, one fewer cross-package test coupling.
	if _, err := svc.repo.db.Exec(ctx, `UPDATE users SET status = 'suspended' WHERE phone = $1`, phone); err != nil {
		t.Fatalf("failed to suspend test user: %v", err)
	}

	_, err := svc.Login(ctx, LoginRequest{Identifier: phone, Password: "the-real-password-1"}, "test-agent", "127.0.0.1")
	if !errors.Is(err, ErrAccountSuspended) {
		t.Errorf("Login() on a suspended account = %v, want ErrAccountSuspended", err)
	}
}

func TestLogin_Success_IssuesTokens(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()
	phone := uniquePhone(t)
	mustCreateActiveUser(t, ctx, svc.repo.db, phone, "the-real-password-1")

	resp, err := svc.Login(ctx, LoginRequest{Identifier: phone, Password: "the-real-password-1"}, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("Login() error: %v", err)
	}
	if resp.AccessToken == "" || resp.RefreshToken == "" {
		t.Error("Login() succeeded but returned an empty token")
	}
	if resp.User.Phone == nil || *resp.User.Phone != phone {
		t.Errorf("Login() returned user phone %v, want %s", resp.User.Phone, phone)
	}
}

// TestLogin_RateLimited is a regression test for BUG-H10: without the
// per-identifier limiter check at the top of Login, an attacker could
// brute-force one account's password indefinitely regardless of how many
// source IPs they spread the attempts across.
func TestLogin_RateLimited(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()
	phone := uniquePhone(t)
	mustCreateActiveUser(t, ctx, svc.repo.db, phone, "the-real-password-1")

	var lastErr error
	for i := 0; i < loginAttemptLimit+2; i++ {
		_, lastErr = svc.Login(ctx, LoginRequest{Identifier: phone, Password: "wrong"}, "test-agent", "127.0.0.1")
	}

	var limitErr *ratelimit.LimitExceededError
	if !errors.As(lastErr, &limitErr) {
		t.Errorf("after %d attempts, Login() = %v, want a *ratelimit.LimitExceededError", loginAttemptLimit+2, lastErr)
	}
}

// TestCreateOTP_InvalidatesPriorActiveCodes is a regression test for the
// OTP lockout bypass fix: CreateOTP must invalidate any still-active code
// for the identifier when a new one is issued, so at most one is ever
// live/guessable at a time. This checks the row count directly rather
// than through VerifyOTP, because GetActiveOTP*'s "newest row wins"
// selection would mask the bug either way — a regression here wouldn't
// change which OTP VerifyOTP finds, only how many rows are simultaneously
// live in the table, which is what the fix actually targets.
func TestCreateOTP_InvalidatesPriorActiveCodes(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()
	phone := uniquePhone(t)
	t.Cleanup(func() {
		_, _ = svc.repo.db.Exec(context.Background(), `DELETE FROM users WHERE phone = $1`, phone)
	})

	if _, err := svc.repo.CreateOTP(ctx, phone, "phone", "login", hashOTP("111111"), time.Now().Add(10*time.Minute)); err != nil {
		t.Fatalf("first CreateOTP() error: %v", err)
	}
	if _, err := svc.repo.CreateOTP(ctx, phone, "phone", "login", hashOTP("222222"), time.Now().Add(10*time.Minute)); err != nil {
		t.Fatalf("second CreateOTP() error: %v", err)
	}

	var activeCount int
	err := svc.repo.db.QueryRow(ctx,
		`SELECT COUNT(*) FROM otp_codes WHERE identifier = $1 AND consumed_at IS NULL AND expires_at > now()`,
		phone).Scan(&activeCount)
	if err != nil {
		t.Fatalf("count query error: %v", err)
	}
	if activeCount != 1 {
		t.Errorf("active OTP count for identifier = %d, want 1 (issuing a new code must invalidate prior ones)", activeCount)
	}
}

// mustCreateActiveUser inserts an already-active, password-set user
// directly (bypassing Signup/VerifyOTP) for tests that only care about
// what happens *after* activation — Login's various outcomes, mainly.
func mustCreateActiveUser(t *testing.T, ctx context.Context, pool *pgxpool.Pool, phone, password string) string {
	t.Helper()
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("bcrypt.GenerateFromPassword: %v", err)
	}
	h := string(hash)

	var userID string
	err = pool.QueryRow(ctx, `
		INSERT INTO users (phone, password_hash, status, phone_verified)
		VALUES ($1, $2, 'active', true)
		RETURNING id`, phone, h).Scan(&userID)
	if err != nil {
		t.Fatalf("mustCreateActiveUser: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, userID) })
	return userID
}

// mustCreateActiveEmailUser mirrors mustCreateActiveUser but for an
// email-identified, passwordless account — the shape a Google signup
// leaves behind once it has cleared the OTP gate, and what a returning
// Google user's row looks like on every login after that.
func mustCreateActiveEmailUser(t *testing.T, ctx context.Context, pool *pgxpool.Pool, email string) string {
	t.Helper()
	var userID string
	err := pool.QueryRow(ctx, `
		INSERT INTO users (email, status, email_verified)
		VALUES ($1, 'active', true)
		RETURNING id`, email).Scan(&userID)
	if err != nil {
		t.Fatalf("mustCreateActiveEmailUser: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, userID) })
	return userID
}

// mustCreatePendingEmailUser is what a phone/email signup leaves behind if
// it's abandoned before the OTP is verified — the state googleAuthForEmail
// must also gate behind an OTP challenge, rather than silently activating.
func mustCreatePendingEmailUser(t *testing.T, ctx context.Context, pool *pgxpool.Pool, email string) string {
	t.Helper()
	var userID string
	err := pool.QueryRow(ctx, `
		INSERT INTO users (email, status)
		VALUES ($1, 'pending')
		RETURNING id`, email).Scan(&userID)
	if err != nil {
		t.Fatalf("mustCreatePendingEmailUser: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, userID) })
	return userID
}

// ---- googleAuthForEmail: the part of GoogleAuth reachable without a live
// Google ID token (see the comment on googleAuthForEmail itself) ----

// TestGoogleAuthForEmail_NewUser_SignsInDirectly pins the fix for a bug
// where a brand-new Google signup was challenged with a second OTP even
// though Google already verified the email as part of issuing the ID
// token (GoogleAuth rejects the token otherwise) — there was nothing left
// for that OTP to actually prove, and it contradicted this very function's
// own doc comment, which always said sign-in should be direct.
func TestGoogleAuthForEmail_NewUser_SignsInDirectly(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()
	email := uniqueEmail(t)

	resp, err := svc.googleAuthForEmail(ctx, email, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("googleAuthForEmail() error: %v", err)
	}

	if resp.OTPRequired {
		t.Fatal("a brand-new Google signup should sign in directly, not require a second OTP")
	}
	if resp.AccessToken == "" || resp.RefreshToken == "" {
		t.Error("tokens should be issued immediately for a new Google signup")
	}
	if resp.User == nil || resp.User.Email == nil || *resp.User.Email != email {
		t.Errorf("resp.User = %+v, want email %q", resp.User, email)
	}

	user, err := svc.repo.GetUserByIdentifier(ctx, email)
	if err != nil {
		t.Fatalf("GetUserByIdentifier() error: %v", err)
	}
	t.Cleanup(func() { _, _ = svc.repo.db.Exec(ctx, `DELETE FROM users WHERE id = $1`, user.ID) })
	if user.Status != "active" {
		t.Errorf("new Google signup's status = %q, want active immediately", user.Status)
	}
}

func TestGoogleAuthForEmail_PendingUser_ActivatesDirectly(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()
	email := uniqueEmail(t)
	mustCreatePendingEmailUser(t, ctx, svc.repo.db, email)

	resp, err := svc.googleAuthForEmail(ctx, email, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("googleAuthForEmail() error: %v", err)
	}
	if resp.OTPRequired {
		t.Error("finishing a pending phone/email signup via Google should not require another OTP")
	}
	if resp.AccessToken == "" {
		t.Error("tokens should be issued once Google activates the pending account")
	}

	activated, err := svc.repo.GetUserByIdentifier(ctx, email)
	if err != nil {
		t.Fatalf("GetUserByIdentifier() error: %v", err)
	}
	if activated.Status != "active" {
		t.Errorf("status after Google auth = %q, want active", activated.Status)
	}
}

func TestGoogleAuthForEmail_ActiveUser_SignsInWithoutOTP(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()
	email := uniqueEmail(t)
	mustCreateActiveEmailUser(t, ctx, svc.repo.db, email)

	resp, err := svc.googleAuthForEmail(ctx, email, "test-agent", "127.0.0.1")
	if err != nil {
		t.Fatalf("googleAuthForEmail() error: %v", err)
	}

	if resp.OTPRequired {
		t.Error("a returning, already-active account should not be re-challenged on every login")
	}
	if resp.AccessToken == "" || resp.RefreshToken == "" {
		t.Error("an already-active account should be signed in directly")
	}
	if resp.User == nil || resp.User.Email == nil || *resp.User.Email != email {
		t.Errorf("resp.User = %+v, want email %q", resp.User, email)
	}
}

func TestGoogleAuthForEmail_SuspendedUser_ReturnsErrAccountSuspended(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()
	email := uniqueEmail(t)
	userID := mustCreateActiveEmailUser(t, ctx, svc.repo.db, email)

	if _, err := svc.repo.db.Exec(ctx, `UPDATE users SET status = 'suspended' WHERE id = $1`, userID); err != nil {
		t.Fatalf("failed to suspend test user: %v", err)
	}

	_, err := svc.googleAuthForEmail(ctx, email, "test-agent", "127.0.0.1")
	if !errors.Is(err, ErrAccountSuspended) {
		t.Errorf("googleAuthForEmail() on a suspended account = %v, want ErrAccountSuspended", err)
	}
}
