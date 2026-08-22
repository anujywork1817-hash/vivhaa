package auth

import (
	"time"

	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
	"matrimony-backend/pkg/ratelimit"
)

// BUG-H10: per-IP limits, complementing the per-identifier limits Service
// enforces (see auth/service.go) — an attacker rotating identifiers from
// one IP, or rotating IPs against one identifier, is stopped by whichever
// of the two layers actually applies to what they're doing.
const (
	otpRequestIPLimit  = 10
	otpRequestIPWindow = 10 * time.Minute

	otpVerifyIPLimit  = 20
	otpVerifyIPWindow = 10 * time.Minute

	loginIPLimit  = 20
	loginIPWindow = 15 * time.Minute
)

// RegisterRoutes mounts the /auth/* endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer, limiter *ratelimit.Limiter) {
	auth := rg.Group("/auth")
	auth.POST("/signup", h.Signup)
	auth.POST("/request-otp",
		middleware.RateLimit(limiter, "otp_request:ip", otpRequestIPLimit, otpRequestIPWindow, middleware.ByIP()),
		h.RequestOTP)
	auth.POST("/verify-otp",
		middleware.RateLimit(limiter, "otp_verify:ip", otpVerifyIPLimit, otpVerifyIPWindow, middleware.ByIP()),
		h.VerifyOTP)
	auth.POST("/google", h.GoogleAuth)
	auth.POST("/login",
		middleware.RateLimit(limiter, "login:ip", loginIPLimit, loginIPWindow, middleware.ByIP()),
		h.Login)
	auth.POST("/refresh-token", h.Refresh)
	auth.POST("/logout", middleware.RequireAuth(issuer), h.Logout)

	auth.POST("/link-phone/request-otp",
		middleware.RequireAuth(issuer),
		middleware.RateLimit(limiter, "otp_request:ip", otpRequestIPLimit, otpRequestIPWindow, middleware.ByIP()),
		h.RequestLinkPhoneOTP)
	auth.POST("/link-phone/verify",
		middleware.RequireAuth(issuer),
		middleware.RateLimit(limiter, "otp_verify:ip", otpVerifyIPLimit, otpVerifyIPWindow, middleware.ByIP()),
		h.ConfirmLinkPhone)
}
