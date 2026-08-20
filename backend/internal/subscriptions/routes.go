package subscriptions

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the /subscriptions/* endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	s := rg.Group("/subscriptions")
	s.Use(middleware.RequireAuth(issuer))

	s.GET("/plans", h.ListPlans)
	s.GET("/me", h.GetMine)
}
