package auth

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"matrimony-backend/pkg/ratelimit"
	"matrimony-backend/pkg/response"
	"matrimony-backend/pkg/validator"
)

type Handler struct {
	service *Service
	// isProd gates the Secure flag on the auth cookies set alongside every
	// token response — Secure cookies are silently dropped by browsers over
	// plain HTTP, which local/LAN dev deployments (see .env's http://
	// API_BASE_URL) still use.
	isProd bool
}

func NewHandler(service *Service, isProd bool) *Handler {
	return &Handler{service: service, isProd: isProd}
}

// setAuthCookies mirrors resp's tokens into httpOnly cookies, in addition
// to (not instead of) the JSON body — the mobile app has no use for
// cookies and keeps working exactly as before via the body; a browser
// client (the admin panel) can opt into reading its session from these
// instead of holding the raw JWTs in JS-accessible storage, which is what
// makes them stealable by an XSS bug in that panel. SameSite=Lax rather
// than None: this only needs to work same-site (the admin panel and API
// share a host, differing only by port, which cookies treat as the same
// site), and Lax avoids the Secure-cookie-required-for-None restriction
// that would otherwise break plain-HTTP LAN deployments entirely.
func (h *Handler) setAuthCookies(c *gin.Context, accessToken, refreshToken string) {
	c.SetSameSite(http.SameSiteLaxMode)
	c.SetCookie("access_token", accessToken, 15*60, "/", "", h.isProd, true)
	c.SetCookie("refresh_token", refreshToken, 30*24*60*60, "/", "", h.isProd, true)
}

func (h *Handler) Signup(c *gin.Context) {
	var req SignupRequest
	if !bindAndValidate(c, &req) {
		return
	}
	if req.Phone == "" && req.Email == "" {
		response.Fail(c, http.StatusBadRequest, "validation_error", "phone or email is required", nil)
		return
	}

	resp, err := h.service.Signup(c.Request.Context(), req)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.Success(c, http.StatusCreated, resp, nil)
}

func (h *Handler) RequestOTP(c *gin.Context) {
	var req RequestOTPRequest
	if !bindAndValidate(c, &req) {
		return
	}

	resp, err := h.service.RequestOTP(c.Request.Context(), req.Identifier)
	if err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, resp)
}

func (h *Handler) GoogleAuth(c *gin.Context) {
	var req GoogleAuthRequest
	if !bindAndValidate(c, &req) {
		return
	}

	resp, err := h.service.GoogleAuth(c.Request.Context(), req.IDToken, c.Request.UserAgent(), c.ClientIP())
	if err != nil {
		writeServiceError(c, err)
		return
	}
	// A first-time signup carries no tokens yet — cookies wait until the
	// OTP challenge above is actually cleared via /auth/verify-otp.
	if !resp.OTPRequired {
		h.setAuthCookies(c, resp.AccessToken, resp.RefreshToken)
	}
	response.OK(c, resp)
}

func (h *Handler) VerifyOTP(c *gin.Context) {
	var req VerifyOTPRequest
	if !bindAndValidate(c, &req) {
		return
	}

	resp, err := h.service.VerifyOTP(c.Request.Context(), req, c.Request.UserAgent(), c.ClientIP())
	if err != nil {
		writeServiceError(c, err)
		return
	}
	h.setAuthCookies(c, resp.AccessToken, resp.RefreshToken)
	response.OK(c, resp)
}

func (h *Handler) Login(c *gin.Context) {
	var req LoginRequest
	if !bindAndValidate(c, &req) {
		return
	}

	resp, err := h.service.Login(c.Request.Context(), req, c.Request.UserAgent(), c.ClientIP())
	if err != nil {
		writeServiceError(c, err)
		return
	}
	h.setAuthCookies(c, resp.AccessToken, resp.RefreshToken)
	response.OK(c, resp)
}

func (h *Handler) Refresh(c *gin.Context) {
	var req RefreshTokenRequest
	if !bindAndValidate(c, &req) {
		return
	}

	resp, err := h.service.RefreshToken(c.Request.Context(), req, c.Request.UserAgent(), c.ClientIP())
	if err != nil {
		writeServiceError(c, err)
		return
	}
	h.setAuthCookies(c, resp.AccessToken, resp.RefreshToken)
	response.OK(c, resp)
}

func (h *Handler) Logout(c *gin.Context) {
	var req LogoutRequest
	if !bindAndValidate(c, &req) {
		return
	}

	userID := c.GetString("user_id")
	if err := h.service.Logout(c.Request.Context(), userID, req); err != nil {
		writeServiceError(c, err)
		return
	}
	response.OK(c, gin.H{"message": "logged out"})
}

func bindAndValidate(c *gin.Context, req interface{}) bool {
	if err := c.ShouldBindJSON(req); err != nil {
		response.Fail(c, http.StatusBadRequest, "invalid_body", "request body is invalid", err.Error())
		return false
	}
	if fieldErrors := validator.Struct(req); fieldErrors != nil {
		response.Fail(c, http.StatusBadRequest, "validation_error", "one or more fields are invalid", fieldErrors)
		return false
	}
	return true
}

func writeServiceError(c *gin.Context, err error) {
	var limitErr *ratelimit.LimitExceededError
	if errors.As(err, &limitErr) {
		retrySeconds := int(limitErr.RetryAfter.Seconds())
		c.Header("Retry-After", strconv.Itoa(retrySeconds))
		response.Fail(c, http.StatusTooManyRequests, "rate_limited",
			"too many requests, please try again later", gin.H{"retry_after_seconds": retrySeconds})
		return
	}

	switch {
	case errors.Is(err, ErrAlreadyRegistered):
		response.Fail(c, http.StatusConflict, "already_registered", err.Error(), nil)
	case errors.Is(err, ErrInvalidCredentials):
		response.Fail(c, http.StatusUnauthorized, "invalid_credentials", err.Error(), nil)
	case errors.Is(err, ErrAccountNotActive):
		response.Fail(c, http.StatusForbidden, "account_not_active", err.Error(), nil)
	case errors.Is(err, ErrAccountSuspended):
		response.Fail(c, http.StatusForbidden, "account_suspended", err.Error(), nil)
	case errors.Is(err, ErrOTPNotFound):
		response.Fail(c, http.StatusBadRequest, "otp_not_found", err.Error(), nil)
	case errors.Is(err, ErrOTPInvalid):
		response.Fail(c, http.StatusBadRequest, "otp_invalid", err.Error(), nil)
	case errors.Is(err, ErrOTPTooManyAttempts):
		response.Fail(c, http.StatusTooManyRequests, "otp_too_many_attempts", err.Error(), nil)
	case errors.Is(err, ErrRefreshTokenInvalid):
		response.Fail(c, http.StatusUnauthorized, "invalid_refresh_token", err.Error(), nil)
	case errors.Is(err, ErrGoogleTokenInvalid):
		response.Fail(c, http.StatusUnauthorized, "invalid_google_token", err.Error(), nil)
	case errors.Is(err, ErrGoogleNotConfigured):
		response.Fail(c, http.StatusServiceUnavailable, "google_not_configured", err.Error(), nil)
	case errors.Is(err, ErrNotFound):
		response.Fail(c, http.StatusNotFound, "not_found", err.Error(), nil)
	default:
		response.Fail(c, http.StatusInternalServerError, "internal_error", "something went wrong", nil)
	}
}
