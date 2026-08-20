package verification

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts /verification/* (user) and /admin/verifications/*
// (admin-only review queue) on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	v := rg.Group("/verification")
	v.Use(middleware.RequireAuth(issuer))
	v.POST("/id", h.Submit)
	v.GET("/me", h.GetMine)

	admin := rg.Group("/admin/verifications")
	admin.Use(middleware.RequireAuth(issuer), middleware.RequireRole("admin"))
	admin.GET("", h.ListPending)
	admin.PUT("/:id/approve", h.Approve)
	admin.PUT("/:id/reject", h.Reject)
}
