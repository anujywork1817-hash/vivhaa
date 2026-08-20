package profiles

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the /profiles/* endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	profiles := rg.Group("/profiles")
	profiles.Use(middleware.RequireAuth(issuer))

	profiles.POST("", h.Create)
	profiles.GET("/me", h.GetMe)
	profiles.PUT("/me", h.UpdateMe)
	profiles.PUT("/me/location", h.UpdateLocation)
	profiles.GET("/:id", h.GetByID)
	profiles.GET("/:id/contact", h.GetContactInfo)
	profiles.POST("/me/photos", h.UploadPhoto)
	profiles.PUT("/me/photos/:photoId/primary", h.SetPrimaryPhoto)
	profiles.DELETE("/me/photos/:photoId", h.DeletePhoto)

	// A sibling top-level route, not nested under /profiles/:id — Gin's
	// router can't have a static segment ("code") and a param (":id") both
	// registered at the same path position.
	rg.GET("/profile-code/:code", middleware.RequireAuth(issuer), h.GetByCode)
}
