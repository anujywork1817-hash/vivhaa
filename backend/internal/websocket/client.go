package websocket

import (
	"time"

	"github.com/gorilla/websocket"
)

const (
	writeWait    = 10 * time.Second
	pongWait     = 60 * time.Second
	pingInterval = (pongWait * 9) / 10
	// 4096 was sized for chat text messages; this connection now also
	// carries WebRTC call signaling (internal/calls), whose SDP
	// offer/answer payloads routinely run several KB once every codec
	// profile and extension a modern device advertises is included —
	// comfortably enough to blow past 4096 and get the connection killed
	// by Gorilla with close code 1009 ("message too big") before the
	// message is ever read, let alone processed. 64KB leaves generous
	// headroom for that while still bounding against abuse.
	maxMessageSize = 65536
)

// MessageHandler processes one inbound message from a connected user.
type MessageHandler func(userID string, raw []byte)

// DisconnectHandler is invoked once this specific connection closes,
// after it's been unregistered from the hub — e.g. so a feature with
// live server-side state tied to a connection (an in-progress call) can
// clean up when the client disappears without sending an explicit
// "I'm done" message first (killed app, lost network, etc.).
type DisconnectHandler func(userID string)

type Client struct {
	hub    *Hub
	conn   *websocket.Conn
	userID string
	send   chan []byte
}

// Serve registers the client with the hub and blocks until the connection
// closes, running the read and write pumps concurrently. onMessage is
// invoked for every inbound message; onDisconnect (may be nil) once the
// connection has closed and been unregistered.
func Serve(hub *Hub, conn *websocket.Conn, userID string, onMessage MessageHandler, onDisconnect DisconnectHandler) {
	c := &Client{hub: hub, conn: conn, userID: userID, send: make(chan []byte, 32)}
	hub.register(c)

	done := make(chan struct{})
	go func() {
		c.writePump()
		close(done)
	}()
	c.readPump(onMessage)
	<-done
	if onDisconnect != nil {
		onDisconnect(userID)
	}
}

func (c *Client) readPump(onMessage MessageHandler) {
	defer func() {
		c.hub.unregister(c)
		close(c.send)
		_ = c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		return c.conn.SetReadDeadline(time.Now().Add(pongWait))
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			return
		}
		onMessage(c.userID, message)
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(pingInterval)
	defer func() {
		ticker.Stop()
		_ = c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				_ = c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
