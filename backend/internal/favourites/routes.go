package favourites

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the /favourites/* endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer, requireUnlocked gin.HandlerFunc) {
	f := rg.Group("/favourites")
	f.Use(middleware.RequireAuth(issuer), requireUnlocked)

	f.GET("", h.List)
	f.POST("/:profileId", h.Add)
	f.DELETE("/:profileId", h.Remove)
}
