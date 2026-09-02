package shortlisted

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the /shortlisted/* endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer, requireUnlocked gin.HandlerFunc) {
	s := rg.Group("/shortlisted")
	s.Use(middleware.RequireAuth(issuer), requireUnlocked)

	s.GET("", h.List)
	s.POST("/:profileId", h.Add)
	s.DELETE("/:profileId", h.Remove)
}
