package demo

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts GET /demo/swipe-deck — auth required, but
// deliberately NOT behind middleware.RequireUnlocked: this is the free
// hook every user sees before the ₹1 unlock paywall.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	d := rg.Group("/demo")
	d.Use(middleware.RequireAuth(issuer))

	d.GET("/swipe-deck", h.SwipeDeck)
}
