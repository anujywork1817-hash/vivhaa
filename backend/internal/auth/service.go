package auth

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"

	"matrimony-backend/internal/analytics"
	"matrimony-backend/internal/email"
	"matrimony-backend/internal/sms"
	"matrimony-backend/pkg/googleauth"
	"matrimony-backend/pkg/jwt"
	"matrimony-backend/pkg/ratelimit"
)

var (
	ErrAlreadyRegistered   = errors.New("identifier already registered")
	ErrInvalidCredentials  = errors.New("invalid credentials")
	ErrAccountNotActive    = errors.New("account not verified")
	ErrAccountSuspended    = errors.New("account has been suspended")
	ErrOTPNotFound         = errors.New("otp not found or expired")
	ErrOTPInvalid          = errors.New("invalid otp code")
	ErrOTPTooManyAttempts  = errors.New("too many otp attempts, request a new code")
	ErrRefreshTokenInvalid = errors.New("invalid or expired refresh token")
	ErrGoogleTokenInvalid  = errors.New("invalid or unverified google account")
	ErrGoogleNotConfigured = errors.New("google sign-in is not configured on this server")
	ErrPhoneAlreadyLinked  = errors.New("this phone number is already linked to an account")
)

const otpTTL = 10 * time.Minute
const otpMaxAttempts = 5

// Per-identifier rate limits (BUG-H10). IP-based limits for the same two
// endpoints are applied at the router layer (internal/auth/routes.go) —
// this is the complementary per-account layer, since an attacker
// spreading requests across many IPs but hammering one phone/email still
// needs to be stopped, and vice versa.
const (
	otpRequestLimit  = 3
	otpRequestWindow = 10 * time.Minute

	loginAttemptLimit  = 8
	loginAttemptWindow = 15 * time.Minute
)

type Service struct {
	repo           *Repository
	smsSender      sms.Sender
	emailSender    email.Sender
	accessIssuer   *jwt.Issuer
	refreshTTL     time.Duration
	devMode        bool
	analyticsSvc   *analytics.Service
	googleVerifier *googleauth.Verifier
	limiter        *ratelimit.Limiter
}

func NewService(repo *Repository, smsSender sms.Sender, emailSender email.Sender, accessIssuer *jwt.Issuer, refreshTTL time.Duration, devMode bool, analyticsSvc *analytics.Service, googleVerifier *googleauth.Verifier, limiter *ratelimit.Limiter) *Service {
	return &Service{
		repo:           repo,
		smsSender:      smsSender,
		emailSender:    emailSender,
		accessIssuer:   accessIssuer,
		refreshTTL:     refreshTTL,
		devMode:        devMode,
		analyticsSvc:   analyticsSvc,
		googleVerifier: googleVerifier,
		limiter:        limiter,
	}
}

func channelFor(phone, email string) (identifier, channel string) {
	if phone != "" {
		return phone, "phone"
	}
	return email, "email"
}

// Signup creates (or resumes) a pending user and sends a signup OTP.
func (s *Service) Signup(ctx context.Context, req SignupRequest) (SignupResponse, error) {
	identifier, channel := channelFor(req.Phone, req.Email)

	var passwordHash *string
	if req.Password != "" {
		hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
		if err != nil {
			return SignupResponse{}, err
		}
		h := string(hash)
		passwordHash = &h
	}

	existing, err := s.repo.GetUserByIdentifier(ctx, identifier)
	switch {
	case err == nil && existing.Status == "active":
		return SignupResponse{}, ErrAlreadyRegistered
	case err == nil && existing.Status == "suspended":
		return SignupResponse{}, ErrAccountSuspended
	case err == nil && existing.Status == "pending":
		if passwordHash != nil {
			if err := s.repo.UpdateUserPassword(ctx, existing.ID, passwordHash); err != nil {
				return SignupResponse{}, err
			}
		}
	case errors.Is(err, ErrNotFound):
		var phonePtr, emailPtr *string
		if channel == "phone" {
			phonePtr = &identifier
		} else {
			emailPtr = &identifier
		}
		if _, err := s.repo.CreateUser(ctx, phonePtr, emailPtr, passwordHash); err != nil {
			return SignupResponse{}, err
		}
	case err != nil:
		return SignupResponse{}, err
	}

	code, err := s.sendOTP(ctx, identifier, channel, "signup")
	if err != nil {
		return SignupResponse{}, err
	}

	resp := SignupResponse{
		Identifier: identifier,
		Channel:    channel,
		Message:    "OTP sent, verify to activate your account",
	}
	if s.devMode {
		resp.DevOTP = code
	}
	return resp, nil
}

func inferChannel(identifier string) string {
	if strings.Contains(identifier, "@") {
		return "email"
	}
	return "phone"
}

// RequestOTP is the single passwordless entry point: it creates a pending
// user if identifier is new, resends a signup OTP if a signup is already
// in progress, or sends a login OTP if the account is already active —
// so the client never needs to know or ask which case applies.
//
// BUG-H10: rate-limited per identifier (a phone/email can only request so
// many OTPs in a window, regardless of source IP) before anything else
// happens — checked first so a locked-out identifier never even reaches
// the DB lookup/OTP-send path.
func (s *Service) RequestOTP(ctx context.Context, identifier string) (SignupResponse, error) {
	if err := s.limiter.Allow(ctx, "otp_request:identifier:"+identifier, otpRequestLimit, otpRequestWindow); err != nil {
		return SignupResponse{}, err
	}

	channel := inferChannel(identifier)
	purpose := "signup"

	existing, err := s.repo.GetUserByIdentifier(ctx, identifier)
	switch {
	case err == nil && existing.Status == "active":
		purpose = "login"
	case err == nil && existing.Status == "suspended":
		return SignupResponse{}, ErrAccountSuspended
	case err == nil && existing.Status == "pending":
		// fall through: resend a signup OTP below
	case errors.Is(err, ErrNotFound):
		var phonePtr, emailPtr *string
		if channel == "phone" {
			phonePtr = &identifier
		} else {
			emailPtr = &identifier
		}
		if _, err := s.repo.CreateUser(ctx, phonePtr, emailPtr, nil); err != nil {
			return SignupResponse{}, err
		}
	case err != nil:
		return SignupResponse{}, err
	}

	code, err := s.sendOTP(ctx, identifier, channel, purpose)
	if err != nil {
		return SignupResponse{}, err
	}

	resp := SignupResponse{
		Identifier: identifier,
		Channel:    channel,
		Message:    "OTP sent",
	}
	if s.devMode {
		resp.DevOTP = code
	}
	return resp, nil
}

func (s *Service) sendOTP(ctx context.Context, identifier, channel, purpose string) (string, error) {
	code, err := generateOTPCode()
	if err != nil {
		return "", err
	}

	if _, err := s.repo.CreateOTP(ctx, identifier, channel, purpose, hashOTP(code), time.Now().Add(otpTTL)); err != nil {
		return "", err
	}

	message := fmt.Sprintf("Your verification code is %s. It expires in %d minutes.", code, int(otpTTL.Minutes()))
	if channel == "phone" {
		if err := s.smsSender.Send(ctx, identifier, message); err != nil {
			return "", err
		}
	} else {
		if err := s.emailSender.Send(ctx, identifier, "Your verification code", message); err != nil {
			return "", err
		}
	}
	return code, nil
}

// VerifyOTP validates a code, activates the account on first signup
// verification, and issues a fresh token pair (auto-login).
func (s *Service) VerifyOTP(ctx context.Context, req VerifyOTPRequest, userAgent, ip string) (AuthResponse, error) {
	var otp OTP
	var err error
	if req.Purpose != "" {
		otp, err = s.repo.GetActiveOTP(ctx, req.Identifier, req.Purpose)
	} else {
		otp, err = s.repo.GetActiveOTPAnyPurpose(ctx, req.Identifier)
	}
	if errors.Is(err, ErrNotFound) {
		return AuthResponse{}, ErrOTPNotFound
	}
	if err != nil {
		return AuthResponse{}, err
	}

	if otp.Attempts >= otp.MaxAttempts {
		return AuthResponse{}, ErrOTPTooManyAttempts
	}

	if !compareOTP(req.Code, otp.CodeHash) {
		_ = s.repo.IncrementOTPAttempts(ctx, otp.ID)
		return AuthResponse{}, ErrOTPInvalid
	}

	if err := s.repo.ConsumeOTP(ctx, otp.ID); err != nil {
		return AuthResponse{}, err
	}

	user, err := s.repo.GetUserByIdentifier(ctx, req.Identifier)
	if err != nil {
		return AuthResponse{}, err
	}

	// Verifying a code only ever proves ownership of the phone/email — it
	// must never be able to lift a suspension. Signup()/RequestOTP()
	// already refuse to hand a suspended account a fresh OTP, but this is
	// the actual gate that decides whether to activate the account, so it
	// checks independently rather than trusting those upstream guards
	// alone (an outstanding OTP issued before a suspension, for example,
	// would otherwise still be valid here).
	if user.Status == "suspended" {
		return AuthResponse{}, ErrAccountSuspended
	}

	if user.Status != "active" {
		if err := s.repo.MarkVerified(ctx, user.ID, otp.Channel); err != nil {
			return AuthResponse{}, err
		}
		user.Status = "active"

		if otp.Purpose == "signup" {
			_ = s.analyticsSvc.Track(ctx, "signup", &user.ID, map[string]string{"channel": otp.Channel})
		}
	}

	return s.issueTokens(ctx, user, userAgent, ip)
}

// GoogleAuth verifies a Google ID token and logs the caller in, creating
// an account on first sign-in. Google already verifies the email as part
// of issuing the token, so a first-time Google account goes straight to
// active — there's no separate OTP step to prove ownership of it.
func (s *Service) GoogleAuth(ctx context.Context, idToken, userAgent, ip string) (GoogleAuthResponse, error) {
	if !s.googleVerifier.Configured() {
		return GoogleAuthResponse{}, ErrGoogleNotConfigured
	}

	claims, err := s.googleVerifier.Verify(ctx, idToken)
	if err != nil || !claims.EmailVerified {
		return GoogleAuthResponse{}, ErrGoogleTokenInvalid
	}

	return s.googleAuthForEmail(ctx, claims.Email, userAgent, ip)
}

// googleAuthForEmail is everything GoogleAuth does once the ID token has
// already been proven to belong to a real, email_verified Google account —
// split out purely so it can be unit tested without a live Google token,
// which *Verifier has no way to fake.
func (s *Service) googleAuthForEmail(ctx context.Context, email, userAgent, ip string) (GoogleAuthResponse, error) {
	user, err := s.repo.GetUserByIdentifier(ctx, email)
	switch {
	case errors.Is(err, ErrNotFound):
		created, err := s.repo.CreateUser(ctx, nil, &email, nil)
		if err != nil {
			return GoogleAuthResponse{}, err
		}
		user = created
		_ = s.analyticsSvc.Track(ctx, "signup_started", nil, map[string]string{"channel": "google"})
	case err != nil:
		return GoogleAuthResponse{}, err
	case user.Status == "suspended":
		return GoogleAuthResponse{}, ErrAccountSuspended
	}

	// Google already verified this email as part of issuing the ID token
	// (GoogleAuth rejects it above otherwise), so — unlike phone/email
	// signup, which has nothing else vouching for the address — there's
	// nothing left for a follow-up OTP to actually prove. A brand-new
	// account, or one left pending by an earlier unfinished phone/email
	// signup for the same address, goes straight to active here instead
	// of being challenged again.
	if user.Status != "active" {
		if err := s.repo.MarkVerified(ctx, user.ID, "email"); err != nil {
			return GoogleAuthResponse{}, err
		}
		user.Status = "active"
		_ = s.analyticsSvc.Track(ctx, "signup", &user.ID, map[string]string{"channel": "google"})
	} else if err := s.repo.UpdateLastLogin(ctx, user.ID); err != nil {
		return GoogleAuthResponse{}, err
	}

	auth, err := s.issueTokens(ctx, user, userAgent, ip)
	if err != nil {
		return GoogleAuthResponse{}, err
	}
	return GoogleAuthResponse{
		AccessToken:  auth.AccessToken,
		RefreshToken: auth.RefreshToken,
		ExpiresAt:    auth.ExpiresAt,
		User:         &auth.User,
	}, nil
}

// RequestLinkPhone starts attaching a phone number to an existing account
// that has none — a Google or email signup never gets one, which used to
// mean the chat contact-share feature could only ever hand out that
// account's email, regardless of what the two members actually meant to
// exchange. Sends an OTP to the new number the same way signup does;
// ConfirmLinkPhone finishes the job once it's verified.
func (s *Service) RequestLinkPhone(ctx context.Context, userID, phone string) (string, error) {
	if err := s.limiter.Allow(ctx, "link_phone:user:"+userID, otpRequestLimit, otpRequestWindow); err != nil {
		return "", err
	}

	if existing, err := s.repo.GetUserByIdentifier(ctx, phone); err == nil && existing.ID != userID {
		return "", ErrPhoneAlreadyLinked
	} else if err != nil && !errors.Is(err, ErrNotFound) {
		return "", err
	}

	code, err := s.sendOTP(ctx, phone, "phone", "link_phone")
	if err != nil {
		return "", err
	}
	if !s.devMode {
		return "", nil
	}
	return code, nil
}

// ConfirmLinkPhone verifies the code RequestLinkPhone sent and, on
// success, attaches phone to userID's account.
func (s *Service) ConfirmLinkPhone(ctx context.Context, userID, phone, code string) error {
	otp, err := s.repo.GetActiveOTP(ctx, phone, "link_phone")
	if errors.Is(err, ErrNotFound) {
		return ErrOTPNotFound
	}
	if err != nil {
		return err
	}
	if otp.Attempts >= otp.MaxAttempts {
		return ErrOTPTooManyAttempts
	}
	if !compareOTP(code, otp.CodeHash) {
		_ = s.repo.IncrementOTPAttempts(ctx, otp.ID)
		return ErrOTPInvalid
	}
	if err := s.repo.ConsumeOTP(ctx, otp.ID); err != nil {
		return err
	}

	// Re-checked here, not just in RequestLinkPhone: the number could have
	// been claimed by someone else in the time between requesting and
	// verifying this code.
	if existing, err := s.repo.GetUserByIdentifier(ctx, phone); err == nil && existing.ID != userID {
		return ErrPhoneAlreadyLinked
	} else if err != nil && !errors.Is(err, ErrNotFound) {
		return err
	}

	return s.repo.LinkPhone(ctx, userID, phone)
}

// Login authenticates with identifier + password.
// BUG-H10: rate-limited per identifier before the password is even
// checked — brute-force protection against guessing one account's
// password has to key on the account being targeted, not just the
// source IP (an attacker can trivially rotate IPs; they can't rotate
// which account they're trying to break into).
func (s *Service) Login(ctx context.Context, req LoginRequest, userAgent, ip string) (AuthResponse, error) {
	if err := s.limiter.Allow(ctx, "login:identifier:"+req.Identifier, loginAttemptLimit, loginAttemptWindow); err != nil {
		return AuthResponse{}, err
	}

	user, err := s.repo.GetUserByIdentifier(ctx, req.Identifier)
	if errors.Is(err, ErrNotFound) {
		return AuthResponse{}, ErrInvalidCredentials
	}
	if err != nil {
		return AuthResponse{}, err
	}

	if user.PasswordHash == nil {
		return AuthResponse{}, ErrInvalidCredentials
	}
	if err := bcrypt.CompareHashAndPassword([]byte(*user.PasswordHash), []byte(req.Password)); err != nil {
		return AuthResponse{}, ErrInvalidCredentials
	}

	if user.Status == "suspended" {
		return AuthResponse{}, ErrAccountSuspended
	}
	if user.Status != "active" {
		return AuthResponse{}, ErrAccountNotActive
	}

	if err := s.repo.UpdateLastLogin(ctx, user.ID); err != nil {
		return AuthResponse{}, err
	}

	return s.issueTokens(ctx, user, userAgent, ip)
}

// RefreshToken rotates a valid refresh token for a new access/refresh pair.
func (s *Service) RefreshToken(ctx context.Context, req RefreshTokenRequest, userAgent, ip string) (AuthResponse, error) {
	hash := hashRefreshToken(req.RefreshToken)

	stored, err := s.repo.GetRefreshToken(ctx, hash)
	if errors.Is(err, ErrNotFound) {
		return AuthResponse{}, ErrRefreshTokenInvalid
	}
	if err != nil {
		return AuthResponse{}, err
	}

	// Revoke before even looking the user up: whatever happens next, this
	// refresh token must not be usable again — an old token surviving a
	// suspension (or a lookup error) would defeat the point of this check.
	if err := s.repo.RevokeRefreshToken(ctx, hash); err != nil {
		return AuthResponse{}, err
	}

	user, err := s.repo.GetUserByID(ctx, stored.UserID)
	if errors.Is(err, ErrNotFound) {
		// Deleted account — GetUserByID already excludes soft-deleted
		// rows. Report this exactly like any other invalid refresh token
		// rather than leaking that the account specifically no longer
		// exists.
		return AuthResponse{}, ErrRefreshTokenInvalid
	}
	if err != nil {
		return AuthResponse{}, err
	}
	// Login()/Signup() already refuse a suspended account new tokens —
	// refresh was the gap: rotating a token only ever checked the token
	// itself, never the account it belongs to, so a suspension didn't
	// actually cut a signed-in session off until its refresh token's full
	// TTL (up to JWT_REFRESH_TTL_HOURS) expired on its own.
	if user.Status == "suspended" {
		return AuthResponse{}, ErrAccountSuspended
	}

	return s.issueTokens(ctx, user, userAgent, ip)
}

// Logout revokes a refresh token belonging to the authenticated user.
func (s *Service) Logout(ctx context.Context, userID string, req LogoutRequest) error {
	hash := hashRefreshToken(req.RefreshToken)
	return s.repo.RevokeRefreshTokenForUser(ctx, userID, hash)
}

func (s *Service) issueTokens(ctx context.Context, user User, userAgent, ip string) (AuthResponse, error) {
	accessToken, expiresAt, err := s.accessIssuer.Generate(user.ID, user.Role)
	if err != nil {
		return AuthResponse{}, err
	}

	refreshToken, err := generateRefreshToken()
	if err != nil {
		return AuthResponse{}, err
	}

	if err := s.repo.CreateRefreshToken(ctx, user.ID, hashRefreshToken(refreshToken), time.Now().Add(s.refreshTTL), userAgent, ip); err != nil {
		return AuthResponse{}, err
	}

	return AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresAt:    expiresAt.Format(time.RFC3339),
		User: UserBrief{
			ID:    user.ID,
			Phone: user.Phone,
			Email: user.Email,
			Role:  user.Role,
		},
	}, nil
}
