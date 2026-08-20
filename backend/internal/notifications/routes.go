package notifications

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the /notifications/* endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	n := rg.Group("/notifications")
	n.Use(middleware.RequireAuth(issuer))

	n.GET("", h.List)
	n.PUT("/read-all", h.MarkAllRead)
	n.PUT("/:id/read", h.MarkRead)
}
