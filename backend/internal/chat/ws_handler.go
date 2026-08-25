package chat

import (
	"context"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	gorillaws "github.com/gorilla/websocket"

	"matrimony-backend/internal/calls"
	appwebsocket "matrimony-backend/internal/websocket"
	appjwt "matrimony-backend/pkg/jwt"
)

// WSHandler serves the single /ws/chat connection shared by chat messaging
// and call signaling — one socket per client, multiplexed by a "type"
// field on each inbound frame (calls.IsCallType), rather than a second
// connection or a separate realtime stack for calls.
type WSHandler struct {
	service      *Service
	callsService *calls.Service
	hub          *appwebsocket.Hub
	issuer       *appjwt.Issuer
	upgrader     gorillaws.Upgrader
}

// NewWSHandler builds the handler. allowAllOrigins/allowedOrigins mirror
// the REST API's own CORS config (cfg.CORS) — a native mobile client
// sends no Origin header at all (only browsers do), so CheckOrigin only
// ever needs to reject a *browser* connecting from an origin outside the
// same allowlist the REST API already enforces; it was previously
// unconditionally `true`, disabling same-origin enforcement entirely and
// leaving /ws/chat open to cross-site WebSocket hijacking (CSWSH) from
// any page that could get a victim's token into script.
func NewWSHandler(service *Service, callsService *calls.Service, hub *appwebsocket.Hub, issuer *appjwt.Issuer, allowAllOrigins bool, allowedOrigins []string) *WSHandler {
	return &WSHandler{
		service:      service,
		callsService: callsService,
		hub:          hub,
		issuer:       issuer,
		upgrader: gorillaws.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			CheckOrigin: func(r *http.Request) bool {
				origin := r.Header.Get("Origin")
				if origin == "" {
					// No Origin header — not a browser (native app, or a
					// non-browser HTTP client), so there's no cross-site
					// context to protect against here.
					return true
				}
				if allowAllOrigins {
					return true
				}
				for _, allowed := range allowedOrigins {
					if strings.EqualFold(strings.TrimSpace(allowed), origin) {
						return true
					}
				}
				return false
			},
		},
	}
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

	conn, err := h.upgrader.Upgrade(c.Writer, c.Request, nil)
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
