package ai

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the /ai/* endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	a := rg.Group("/ai")
	a.Use(middleware.RequireAuth(issuer))

	a.POST("/chat", h.Chat)
	a.GET("/messages", h.History)
	a.GET("/icebreakers/:profileId", h.Icebreakers)
	a.GET("/match-blurb/:profileId", h.MatchBlurb)
}
