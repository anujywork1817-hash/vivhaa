package chat

import (
	"context"
	"net/http"

	"github.com/gin-gonic/gin"
	gorillaws "github.com/gorilla/websocket"

	"matrimony-backend/internal/calls"
	appwebsocket "matrimony-backend/internal/websocket"
	appjwt "matrimony-backend/pkg/jwt"
)

var upgrader = gorillaws.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// Local/dev CORS is wide open; tighten to known frontend origins before prod.
	CheckOrigin: func(r *http.Request) bool { return true },
}

// WSHandler serves the single /ws/chat connection shared by chat messaging
// and call signaling — one socket per client, multiplexed by a "type"
// field on each inbound frame (calls.IsCallType), rather than a second
// connection or a separate realtime stack for calls.
type WSHandler struct {
	service      *Service
	callsService *calls.Service
	hub          *appwebsocket.Hub
	issuer       *appjwt.Issuer
}

func NewWSHandler(service *Service, callsService *calls.Service, hub *appwebsocket.Hub, issuer *appjwt.Issuer) *WSHandler {
	return &WSHandler{service: service, callsService: callsService, hub: hub, issuer: issuer}
}

// Serve upgrades the connection to a WebSocket after authenticating the
// access token, which may arrive as a Bearer header or a ?token= query
// param (browsers can't set custom headers on the WS handshake).
func (h *WSHandler) Serve(c *gin.Context) {
	token := c.Query("token")
	if token == "" {
		token = extractBearer(c.GetHeader("Authorization"))
	}

	claims, err := h.issuer.Verify(token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "error": gin.H{"code": "unauthorized", "message": "invalid or missing token"}})
		return
	}

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}

	appwebsocket.Serve(h.hub, conn, claims.UserID,
		func(userID string, raw []byte) {
			if calls.IsCallType(raw) {
				h.callsService.HandleIncoming(context.Background(), userID, raw)
				return
			}
			h.service.HandleIncoming(context.Background(), userID, raw)
		},
		func(userID string) {
			h.callsService.HandleDisconnect(userID)
		},
	)
}

func extractBearer(header string) string {
	const prefix = "Bearer "
	if len(header) > len(prefix) && header[:len(prefix)] == prefix {
		return header[len(prefix):]
	}
	return ""
}
