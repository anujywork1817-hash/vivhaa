// Package websocket implements a hub that tracks connected chat clients
// by user ID and lets other packages push events to a user's active
// connections without needing to know about the transport layer.
package websocket

import (
	"context"
	"encoding/json"
	"log/slog"
	"strconv"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

// broadcastChannel is the single Redis pub/sub channel every API instance
// subscribes to. Chosen over one channel per user (which would need each
// instance to SUBSCRIBE/UNSUBSCRIBE as its local connection count for a
// user goes 0<->1) for simplicity — at this app's scale, every instance
// filtering every message locally costs far less than the bugs a dynamic
// per-user subscription set would risk.
const broadcastChannel = "ws:broadcast"

// presenceTTL/presenceRefreshInterval back IsOnline: a user is considered
// online on an instance for presenceTTL after that instance last refreshed
// its entry, refreshed well before expiry so a live connection never
// lapses. TTL (via a Redis sorted-set score, not Redis key expiry — see
// refreshPresence) rather than an explicit "I'm shutting down" message
// means a crashed/killed instance's stale entries self-heal within one
// TTL window instead of leaking forever.
const (
	presenceTTL             = 90 * time.Second
	presenceRefreshInterval = 45 * time.Second
)

// envelope is what actually crosses the Redis pub/sub channel. Every
// instance's subscription receives every envelope regardless of whether
// it has a matching local connection — see broadcastChannel's doc.
type envelope struct {
	UserID  string          `json:"user_id"`
	Payload json.RawMessage `json:"payload"`
}

type Hub struct {
	mu      sync.RWMutex
	clients map[string]map[*Client]bool // userID -> set of local connections (multi-device)

	redis      *redis.Client
	instanceID string
	log        *slog.Logger
}

// NewHub starts the Redis subscription and presence-refresh loops, both
// running for the process lifetime — there's no explicit shutdown hook
// for background work in this codebase (cmd/scheduler's ticker loop is
// the same pattern), so these simply stop when the process exits.
func NewHub(ctx context.Context, redisClient *redis.Client, log *slog.Logger) *Hub {
	h := &Hub{
		clients:    make(map[string]map[*Client]bool),
		redis:      redisClient,
		instanceID: uuid.NewString(),
		log:        log,
	}
	go h.subscribeLoop(ctx)
	go h.presenceRefreshLoop(ctx)
	return h
}

func (h *Hub) register(c *Client) {
	h.mu.Lock()
	_, alreadyOnline := h.clients[c.userID]
	if h.clients[c.userID] == nil {
		h.clients[c.userID] = make(map[*Client]bool)
	}
	h.clients[c.userID][c] = true
	h.mu.Unlock()

	// First local connection for this user — publish presence immediately
	// rather than waiting for the next refresh tick, so IsOnline from
	// another instance reflects a just-connected user right away.
	if !alreadyOnline {
		h.refreshPresenceFor(context.Background(), c.userID)
	}
}

func (h *Hub) unregister(c *Client) {
	h.mu.Lock()
	stillOnline := true
	if conns, ok := h.clients[c.userID]; ok {
		delete(conns, c)
		if len(conns) == 0 {
			delete(h.clients, c.userID)
			stillOnline = false
		}
	}
	h.mu.Unlock()

	if !stillOnline {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := h.redis.ZRem(ctx, presenceKey(c.userID), h.instanceID).Err(); err != nil {
			h.log.Warn("websocket: failed to clear presence on disconnect", "user_id", c.userID, "error", err)
		}
	}
}

// SendToUser publishes message for userID onto the shared broadcast
// channel — every instance (including this one) receives it via
// subscribeLoop and delivers to whichever local connections it has for
// that user, so it doesn't matter which instance originally handled the
// request that led here. It's a no-op (not an error) if the user has no
// active connection anywhere; publish failures are logged, not returned,
// matching the old local-only version's "never blocks/errors the caller"
// contract.
func (h *Hub) SendToUser(userID string, message []byte) {
	payload, err := json.Marshal(envelope{UserID: userID, Payload: message})
	if err != nil {
		h.log.Error("websocket: failed to marshal envelope", "user_id", userID, "error", err)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := h.redis.Publish(ctx, broadcastChannel, payload).Err(); err != nil {
		h.log.Error("websocket: failed to publish message", "user_id", userID, "error", err)
	}
}

// deliverLocal is SendToUser's old body — pushes to every local
// connection for userID, dropping (not blocking) on a full send buffer.
// Only ever called from subscribeLoop now, once per envelope this
// instance receives.
func (h *Hub) deliverLocal(userID string, message []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.clients[userID] {
		select {
		case c.send <- message:
		default:
			// client's send buffer is full/stuck; drop rather than block the hub.
		}
	}
}

// subscribeLoop reads off pubsub.Channel() rather than looping
// ReceiveMessage directly — Channel() is the standard go-redis pattern
// for a long-lived background subscriber and handles reconnection
// internally, so there's no manual retry/backoff needed here.
func (h *Hub) subscribeLoop(ctx context.Context) {
	pubsub := h.redis.Subscribe(ctx, broadcastChannel)
	defer func() { _ = pubsub.Close() }()

	// Forces the SUBSCRIBE confirmation round-trip to complete before
	// Channel() starts its own internal read loop — without this,
	// Channel() can be called while the subscription is still being
	// established and miss the confirmation handshake.
	if _, err := pubsub.Receive(ctx); err != nil {
		if ctx.Err() == nil {
			h.log.Error("websocket: failed to establish redis subscription", "error", err)
		}
		return
	}

	ch := pubsub.Channel()
	for {
		select {
		case <-ctx.Done():
			return
		case msg, ok := <-ch:
			if !ok {
				return // pubsub closed (context canceled or Close() called)
			}
			var env envelope
			if err := json.Unmarshal([]byte(msg.Payload), &env); err != nil {
				h.log.Error("websocket: failed to unmarshal envelope", "error", err)
				continue
			}
			h.deliverLocal(env.UserID, env.Payload)
		}
	}
}

// IsOnline reports whether userID has at least one live connection on any
// instance — a real Redis round-trip now, not a free in-memory read (see
// presenceTTL's doc), since the answer can no longer be known locally.
func (h *Hub) IsOnline(ctx context.Context, userID string) bool {
	count, err := h.redis.ZCount(ctx, presenceKey(userID), strconv.FormatInt(time.Now().Unix(), 10), "+inf").Result()
	if err != nil {
		h.log.Error("websocket: failed to check presence", "user_id", userID, "error", err)
		// Fail open on the underlying online/offline signal would let a
		// Redis blip silently make every callee look unreachable — the
		// one caller of this (calls.Service.initiate) actually wants the
		// opposite failure mode, so this returns "online" and lets the
		// call attempt itself fail/time out normally instead of a
		// misleading "member is offline" on a Redis hiccup.
		return true
	}
	return count > 0
}

// presenceRefreshLoop periodically re-publishes presence for every
// currently-locally-connected user, so a long-lived connection's entry
// never lapses past presenceTTL.
func (h *Hub) presenceRefreshLoop(ctx context.Context) {
	ticker := time.NewTicker(presenceRefreshInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			h.mu.RLock()
			userIDs := make([]string, 0, len(h.clients))
			for userID := range h.clients {
				userIDs = append(userIDs, userID)
			}
			h.mu.RUnlock()

			for _, userID := range userIDs {
				h.refreshPresenceFor(ctx, userID)
			}
		}
	}
}

func (h *Hub) refreshPresenceFor(ctx context.Context, userID string) {
	expiry := time.Now().Add(presenceTTL)
	if err := h.redis.ZAdd(ctx, presenceKey(userID), redis.Z{
		Score: float64(expiry.Unix()), Member: h.instanceID,
	}).Err(); err != nil {
		h.log.Warn("websocket: failed to refresh presence", "user_id", userID, "error", err)
	}
}

func presenceKey(userID string) string {
	return "ws:online:" + userID
}
