package preferences

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts /preferences on the given router group. Both POST
// and PUT perform the same upsert since there's exactly one preferences
// row per user.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	prefs := rg.Group("/preferences")
	prefs.Use(middleware.RequireAuth(issuer))

	prefs.GET("", h.GetMine)
	prefs.POST("", h.Upsert)
	prefs.PUT("", h.Upsert)
}
