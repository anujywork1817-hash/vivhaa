package search

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts /search/profiles on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer, requireUnlocked gin.HandlerFunc) {
	s := rg.Group("/search")
	s.Use(middleware.RequireAuth(issuer), requireUnlocked)

	s.GET("/profiles", h.Search)
}
