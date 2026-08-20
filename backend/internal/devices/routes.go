package devices

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the /devices/* endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	d := rg.Group("/devices")
	d.Use(middleware.RequireAuth(issuer))

	d.POST("/token", h.Register)
	d.DELETE("/token", h.Unregister)
}
