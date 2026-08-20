package calls

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts GET /video-call/ice-servers (any authenticated
// user) and the admin-only GET /admin/call-history (read-only call log
// for moderation/support — admin has no calling capability of its own).
// The actual call signaling (offer/answer/ICE/etc.) doesn't ride a REST
// route at all — it's multiplexed over the same /ws/chat connection
// chat already owns; see chat.WSHandler's dispatch.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, issuer *jwt.Issuer) {
	videoCall := rg.Group("/video-call")
	videoCall.Use(middleware.RequireAuth(issuer))
	videoCall.GET("/ice-servers", h.ICEServers)

	adminGroup := rg.Group("/admin")
	adminGroup.Use(middleware.RequireAuth(issuer), middleware.RequireRole("admin"))
	adminGroup.GET("/call-history", h.AdminListCallHistory)
}
