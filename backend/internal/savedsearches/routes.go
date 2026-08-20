package savedsearches

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the /saved-searches endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	s := rg.Group("/saved-searches")
	s.Use(middleware.RequireAuth(issuer))

	s.GET("", h.List)
	s.POST("", h.Create)
	s.DELETE("/:id", h.Delete)
}
