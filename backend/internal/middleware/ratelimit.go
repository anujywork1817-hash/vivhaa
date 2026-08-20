package middleware

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"matrimony-backend/pkg/ratelimit"
	"matrimony-backend/pkg/response"
)

// RateLimit builds Gin middleware backed by a ratelimit.Limiter. keyFunc
// derives the bucket a given request counts against — different callers
// plug in different keys for different abuse patterns (see ByIP/ByUser/
// ByUserAndParam below). Must run after RequireAuth for any keyFunc that
// reads "user_id" off the context.
func RateLimit(limiter *ratelimit.Limiter, keyPrefix string, limit int, window time.Duration, keyFunc func(c *gin.Context) string) gin.HandlerFunc {
	return func(c *gin.Context) {
		key := keyPrefix + ":" + keyFunc(c)
		err := limiter.Allow(c.Request.Context(), key, limit, window)
		if err == nil {
			c.Next()
			return
		}

		var limitErr *ratelimit.LimitExceededError
		if errors.As(err, &limitErr) {
			retrySeconds := int(limitErr.RetryAfter.Seconds())
			c.Header("Retry-After", strconv.Itoa(retrySeconds))
			response.Fail(c, http.StatusTooManyRequests, "rate_limited",
				"too many requests, please try again later", gin.H{"retry_after_seconds": retrySeconds})
			c.Abort()
			return
		}

		// Redis itself errored (connection blip, etc.) — fail open. Abuse
		// protection degrading for the duration of an infra hiccup is a far
		// smaller problem than the entire API going down because Redis did.
		c.Next()
	}
}

// ByIP rate-limits per client IP — the only key available before a
// request body is parsed, so it's what any pre-auth, pre-bind endpoint
// (like /auth/login) has to key on at the middleware layer. Identifier-
// specific limits (e.g. per phone/email) are enforced inside the
// relevant service instead, once the body is bound.
func ByIP() func(c *gin.Context) string {
	return func(c *gin.Context) string { return c.ClientIP() }
}

// ByUser rate-limits per authenticated user. Must run after RequireAuth.
func ByUser() func(c *gin.Context) string {
	return func(c *gin.Context) string { return c.GetString("user_id") }
}

// ByUserAndParam rate-limits per (authenticated user, URL param) pair —
// e.g. one user's reminders to one specific interest, rather than a
// blanket per-user cap that would also throttle reminding different
// people. Must run after RequireAuth.
func ByUserAndParam(param string) func(c *gin.Context) string {
	return func(c *gin.Context) string { return c.GetString("user_id") + ":" + c.Param(param) }
}
