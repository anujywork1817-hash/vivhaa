package blocked

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the /blocked/* endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	b := rg.Group("/blocked")
	b.Use(middleware.RequireAuth(issuer))

	b.GET("", h.List)
	b.GET("/:profileId/status", h.Status)
	b.POST("/:profileId", h.Block)
	b.DELETE("/:profileId", h.Unblock)
}
