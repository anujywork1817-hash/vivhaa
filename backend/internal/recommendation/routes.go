package recommendation

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the /matches/* endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer, requireUnlocked gin.HandlerFunc) {
	m := rg.Group("/matches")
	m.Use(middleware.RequireAuth(issuer), requireUnlocked)

	m.GET("/recommended", h.Recommended)
	m.GET("/daily", h.Daily)
	m.GET("/all", h.All)
	m.GET("/nearby", h.Nearby)
}
