package auth

import "time"

type User struct {
	ID            string
	Phone         *string
	Email         *string
	PasswordHash  *string
	PhoneVerified bool
	EmailVerified bool
	Status        string
	Role          string
	CreatedAt     time.Time
}

type OTP struct {
	ID          string
	Identifier  string
	Channel     string
	Purpose     string
	CodeHash    string
	Attempts    int16
	MaxAttempts int16
	ExpiresAt   time.Time
	ConsumedAt  *time.Time
}

type RefreshToken struct {
	ID        string
	UserID    string
	TokenHash string
	ExpiresAt time.Time
	RevokedAt *time.Time
}
