package admin

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the admin-only user management and dashboard
// endpoints. Verification/report review queues live in their own
// packages (internal/verification, internal/moderation) but are gated
// the same way.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	admin := rg.Group("/admin")
	admin.Use(middleware.RequireAuth(issuer), middleware.RequireRole("admin"))

	admin.GET("/users", h.ListUsers)
	admin.GET("/users/:id", h.GetUser)
	admin.PUT("/users/:id/suspend", h.Suspend)
	admin.PUT("/users/:id/activate", h.Activate)
	admin.GET("/dashboard", h.Dashboard)
	admin.GET("/subscriptions", h.ListSubscriptions)
	admin.GET("/revenue", h.Revenue)
	admin.GET("/unlock-accounts", h.ListUnlockAccounts)
	admin.GET("/unlock-accounts/summary", h.UnlockRevenueSummary)
}
