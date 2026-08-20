package interests

import (
	"time"

	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
	"matrimony-backend/pkg/ratelimit"
)

// RegisterRoutes mounts the /interests/* endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer, limiter *ratelimit.Limiter) {
	i := rg.Group("/interests")
	i.Use(middleware.RequireAuth(issuer))

	i.POST("/:profileId", h.Express)
	i.PUT("/:id/accept", h.Accept)
	i.PUT("/:id/decline", h.Decline)
	// BUG-H10: one reminder per (user, interest) per hour — keyed on the
	// interest id specifically (not a blanket per-user cap) so reminding
	// different people isn't throttled by hammering one of them.
	i.PUT("/:id/remind", middleware.RateLimit(limiter, "remind", 1, time.Hour, middleware.ByUserAndParam("id")), h.Remind)
	i.DELETE("/:id", h.Delete)
	i.GET("/sent", h.ListSent)
	i.GET("/received", h.ListReceived)
	i.GET("/deleted", h.ListDeleted)
}
