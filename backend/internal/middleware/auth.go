// Package middleware holds cross-cutting Gin middleware (auth guard, etc.)
package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"matrimony-backend/pkg/jwt"
	"matrimony-backend/pkg/response"
)

// RequireAuth validates the Bearer access token and injects "user_id" and
// "role" into the request context for downstream handlers.
func RequireAuth(issuer *jwt.Issuer) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		parts := strings.SplitN(header, " ", 2)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || parts[1] == "" {
			response.Fail(c, http.StatusUnauthorized, "unauthorized", "missing or malformed Authorization header", nil)
			c.Abort()
			return
		}

		claims, err := issuer.Verify(parts[1])
		if err != nil {
			response.Fail(c, http.StatusUnauthorized, "unauthorized", "invalid or expired access token", nil)
			c.Abort()
			return
		}

		c.Set("user_id", claims.UserID)
		c.Set("role", claims.Role)
		c.Next()
	}
}

// RequireRole restricts a route to a specific role; must run after RequireAuth.
func RequireRole(role string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetString("role") != role {
			response.Fail(c, http.StatusForbidden, "forbidden", "insufficient permissions", nil)
			c.Abort()
			return
		}
		c.Next()
	}
}
