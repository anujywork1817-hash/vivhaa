package moderation

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the admin-only /admin/reports/* review queue.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	admin := rg.Group("/admin/reports")
	admin.Use(middleware.RequireAuth(issuer), middleware.RequireRole("admin"))

	admin.GET("", h.ListPending)
	admin.PUT("/:id/resolve", h.Resolve)
}
