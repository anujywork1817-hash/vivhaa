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
		token := bearerToken(c)
		if token == "" {
			// Falls back to the httpOnly cookie auth/handler.go's
			// setAuthCookies mirrors every token response into — a browser
			// client (the admin panel) can rely on this instead of holding
			// the access token in JS-reachable storage; native clients keep
			// using the Authorization header exactly as before.
			if cookie, err := c.Cookie("access_token"); err == nil && cookie != "" {
				token = cookie
			}
		}
		if token == "" {
			response.Fail(c, http.StatusUnauthorized, "unauthorized", "missing or malformed Authorization header", nil)
			c.Abort()
			return
		}

		claims, err := issuer.Verify(token)
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

func bearerToken(c *gin.Context) string {
	header := c.GetHeader("Authorization")
	parts := strings.SplitN(header, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return ""
	}
	return parts[1]
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
