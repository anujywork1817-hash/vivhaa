package auth

type SignupRequest struct {
	Phone    string `json:"phone" validate:"omitempty,e164"`
	Email    string `json:"email" validate:"omitempty,email"`
	Password string `json:"password" validate:"omitempty,min=8"`
}

type SignupResponse struct {
	Identifier string `json:"identifier"`
	Channel    string `json:"channel"`
	Message    string `json:"message"`
	DevOTP     string `json:"dev_otp,omitempty"`
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
