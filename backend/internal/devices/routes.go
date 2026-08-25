package devices

import (
	"time"

	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
	"matrimony-backend/pkg/ratelimit"
)

// RegisterRoutes mounts the /devices/* endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer, limiter *ratelimit.Limiter) {
	d := rg.Group("/devices")
	d.Use(middleware.RequireAuth(issuer))

	// Unlike /auth/*, registering a push token has no proof-of-possession
	// check — any authenticated user can register any token string. A
	// rate limit doesn't fix that on its own, but it does bound how fast
	// someone who obtained a victim's real FCM token via another leak
	// could re-register it to their own account (and how fast a token
	// could be bounced between accounts generally).
	d.POST("/token", middleware.RateLimit(limiter, "device_token", 10, time.Hour, middleware.ByUser()), h.Register)
	d.DELETE("/token", h.Unregister)
}
