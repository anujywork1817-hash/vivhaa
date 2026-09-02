package unlock

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/internal/payments"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts /unlock/* — deliberately NOT behind
// middleware.RequireUnlocked (that would be a lock with no key) and not
// behind the plan-based subscriptions system either; just auth.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer, gateway payments.Gateway) {
	u := rg.Group("/unlock")
	u.Use(middleware.RequireAuth(issuer))

	u.GET("/status", h.Status)
	u.POST("/checkout", h.Checkout)
	u.POST("/verify", h.Verify)

	// Dev-only: stands in for Razorpay's checkout widget completing a
	// payment. Only reachable when the mock gateway is actually active —
	// mirrors payments.RegisterRoutes' identical conditional registration.
	if _, ok := gateway.(*payments.MockGateway); ok {
		u.POST("/mock/complete", h.MockComplete)
	}
}
