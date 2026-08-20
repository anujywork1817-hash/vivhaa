package payments

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the /payments/* endpoints on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer, gateway Gateway) {
	// Webhook is server-to-server (Razorpay calling us) — authenticated via
	// its own HMAC signature (X-Razorpay-Signature), not a user's Bearer
	// token, so it must not sit behind RequireAuth.
	rg.POST("/payments/webhook", h.Webhook)

	p := rg.Group("/payments")
	p.Use(middleware.RequireAuth(issuer))

	p.POST("/checkout", h.Checkout)
	p.POST("/verify", h.Verify)
	p.GET("/history", h.History)

	// Dev-only: stands in for Razorpay's checkout widget completing a
	// payment, which nothing in this backend can simulate on its own.
	// Only reachable when the mock gateway is actually active — never
	// registered against the real one.
	if _, ok := gateway.(*MockGateway); ok {
		p.POST("/mock/complete", h.MockComplete)
	}
}
