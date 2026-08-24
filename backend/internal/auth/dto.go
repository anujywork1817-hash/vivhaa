package auth

type LinkPhoneRequestOTPRequest struct {
	Phone string `json:"phone" validate:"required,e164"`
}

type LinkPhoneVerifyRequest struct {
	Phone string `json:"phone" validate:"required,e164"`
	Code  string `json:"code" validate:"required,len=6,numeric"`
}

// SetPhoneRequest attaches a phone number to the caller's account with no
// OTP round-trip — see Service.SetPhoneUnverified's doc comment for why.
type SetPhoneRequest struct {
	Phone string `json:"phone" validate:"required,e164"`
}

type SignupRequest struct {
	Phone    string `json:"phone" validate:"omitempty,e164"`
	Email    string `json:"email" validate:"omitempty,email"`
	Password string `json:"password" validate:"omitempty,min=8"`
}

// SignupResponse is one of two shapes depending on OTPRequired, same
// convention as GoogleAuthResponse:
//
//   - OTPRequired true: the legacy passwordless path (no password given)
//     — Identifier/Channel/Message/DevOTP are set, and the client must
//     call /auth/verify-otp to finish, same as before this field existed.
//   - OTPRequired false: a password was given. The account activates
//     immediately and the client is signed in right away — a password is
//     proof enough for this platform's threat model going forward;
//     verifying the email/phone is real is deferred to whenever the
//     password is actually needed (see the forgot-password flow, which
//     re-proves the address the same way signup used to for everyone).
type SignupResponse struct {
	OTPRequired bool   `json:"otp_required"`
	Identifier  string `json:"identifier,omitempty"`
	Channel     string `json:"channel,omitempty"`
	Message     string `json:"message,omitempty"`
	DevOTP      string `json:"dev_otp,omitempty"`

	AccessToken  string     `json:"access_token,omitempty"`
	RefreshToken string     `json:"refresh_token,omitempty"`
	ExpiresAt    string     `json:"expires_at,omitempty"`
	User         *UserBrief `json:"user,omitempty"`
}

type ForgotPasswordRequest struct {
	Identifier string `json:"identifier" validate:"required"`
}

type ForgotPasswordResponse struct {
	Message string `json:"message"`
	DevOTP  string `json:"dev_otp,omitempty"`
}

type ResetPasswordRequest struct {
	Identifier  string `json:"identifier" validate:"required"`
	Code        string `json:"code" validate:"required,len=6,numeric"`
	NewPassword string `json:"new_password" validate:"required,min=8"`
}

// RequestOTPRequest is the single passwordless entry point: send an OTP to
// identifier regardless of whether it belongs to a new or returning user.
// The channel (phone vs email) is inferred from the identifier's shape.
type RequestOTPRequest struct {
	Identifier string `json:"identifier" validate:"required"`
}

type VerifyOTPRequest struct {
	Identifier string `json:"identifier" validate:"required"`
	// Purpose is optional: the server already knows what purpose the
	// active OTP for this identifier was issued for, so a client that
	// only ever calls RequestOTP (not the legacy password Signup) never
	// needs to supply it.
	Purpose string `json:"purpose" validate:"omitempty,oneof=signup login"`
	Code    string `json:"code" validate:"required,len=6,numeric"`
}

type GoogleAuthRequest struct {
	IDToken string `json:"id_token" validate:"required"`
}

// GoogleAuthResponse is one of two shapes depending on OTPRequired:
//
//   - OTPRequired true: this is a first-time signup (or an account still
//     pending from an earlier, unfinished phone/email signup). Only
//     Identifier — the Google account's email — is set; the client must
//     call the existing /auth/verify-otp with it to finish, exactly like
//     a phone/email signup.
//   - OTPRequired false: a returning, already-active account. The token
//     fields are set and the client is signed in immediately, same as
//     before this type existed.
//
// Google's own EmailVerified claim already proves the address is real, but
// a matrimony platform's anti-fraud posture wants every signup path —
// Google included — to clear the same one-time code challenge, not get a
// silent bypass. A returning user isn't asked again: Google already
// vouched for this exact sign-in once, at account creation.
type GoogleAuthResponse struct {
	OTPRequired bool   `json:"otp_required"`
	Identifier  string `json:"identifier,omitempty"`
	DevOTP      string `json:"dev_otp,omitempty"`

	AccessToken  string     `json:"access_token,omitempty"`
	RefreshToken string     `json:"refresh_token,omitempty"`
	ExpiresAt    string     `json:"expires_at,omitempty"`
	User         *UserBrief `json:"user,omitempty"`
}

type LoginRequest struct {
	Identifier string `json:"identifier" validate:"required"`
	Password   string `json:"password" validate:"required"`
}

type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token" validate:"required"`
}

type LogoutRequest struct {
	RefreshToken string `json:"refresh_token" validate:"required"`
}

type AuthResponse struct {
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
	ExpiresAt    string    `json:"expires_at"`
	User         UserBrief `json:"user"`
}

type UserBrief struct {
	ID    string  `json:"id"`
	Phone *string `json:"phone"`
	Email *string `json:"email"`
	Role  string  `json:"role"`
}
