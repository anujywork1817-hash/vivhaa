package reports

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts POST /reports/:profileId on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	r := rg.Group("/reports")
	r.Use(middleware.RequireAuth(issuer))

	r.POST("/:profileId", h.Submit)
}
