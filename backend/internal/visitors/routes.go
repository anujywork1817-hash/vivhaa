package visitors

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts GET /visitors ("who viewed my profile") on the
// given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer, requireUnlocked gin.HandlerFunc) {
	v := rg.Group("/visitors")
	v.Use(middleware.RequireAuth(issuer), requireUnlocked)

	v.GET("", h.List)
}
