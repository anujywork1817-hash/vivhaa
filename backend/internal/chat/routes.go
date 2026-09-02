package chat

import (
	"github.com/gin-gonic/gin"

	"matrimony-backend/internal/middleware"
	"matrimony-backend/pkg/jwt"
)

// RegisterRoutes mounts the /chat/* REST endpoints and the /ws/chat
// WebSocket endpoint on the given router group.
func RegisterRoutes(rg *gin.RouterGroup, h *Handler, ws *WSHandler, issuer *jwt.Issuer, requireUnlocked gin.HandlerFunc) {
	chatGroup := rg.Group("/chat")
	chatGroup.Use(middleware.RequireAuth(issuer), requireUnlocked)

	chatGroup.GET("/conversations", h.ListConversations)
	chatGroup.GET("/messages/:userId", h.GetHistory)
	chatGroup.POST("/messages/:userId", h.SendMessage)
	chatGroup.POST("/messages/:userId/attachment", h.UploadAttachment)
	chatGroup.POST("/messages/:userId/contact-request", h.RequestContact)
	chatGroup.POST("/contact-requests/:messageId/accept", h.AcceptContact)
	chatGroup.POST("/contact-requests/:messageId/decline", h.DeclineContact)

	// WS auth is handled inside WSHandler.Serve (token via query param),
	// since the browser WS handshake can't set custom headers.
	rg.GET("/ws/chat", ws.Serve)
}
