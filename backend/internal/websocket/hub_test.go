package websocket

import (
	"context"
	"io"
	"log/slog"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

// newTestClient builds a Client with a buffered send channel but no real
// network connection — the hub only ever touches userID and send, so the
// nil conn is never used by the code under test.
func newTestClient(userID string, buffer int) *Client {
	return &Client{userID: userID, send: make(chan []byte, buffer)}
}

// newTestHub wires a Hub against a real (in-memory) Redis via miniredis —
// SendToUser/IsOnline genuinely round-trip through Redis pub/sub and
// sorted sets here, the same as in production, just against a fake
// server instead of a live one.
func newTestHub(t *testing.T) *Hub {
	t.Helper()
	mr := miniredis.RunT(t)
	// miniredis doesn't fully implement the RESP3 handshake go-redis
	// negotiates by default (v9's client auto-upgrades unless told
	// otherwise) — forcing RESP2 here is purely a test fixture detail, the
	// production client (pkg/redis) doesn't set this and talks to a real
	// Redis that handles RESP3 fine.
	client := redis.NewClient(&redis.Options{Addr: mr.Addr(), Protocol: 2})
	t.Cleanup(func() { _ = client.Close() })

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	h := NewHub(ctx, client, log)
	// subscribeLoop's SUBSCRIBE needs a moment to actually register with
	// miniredis before a PUBLISH sent immediately after would be missed —
	// real Redis has the same subscribe-before-publish requirement, this
	// just makes the race visible at test speed.
	time.Sleep(50 * time.Millisecond)
	return h
}

func waitForDelivery(t *testing.T, ch <-chan []byte, want string) {
	t.Helper()
	select {
	case got := <-ch:
		if string(got) != want {
			t.Errorf("received %q, want %q", got, want)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for delivery")
	}
}

func TestSendToUser_DeliversToAllOfAUsersConnections(t *testing.T) {
	hub := newTestHub(t)

	phone := newTestClient("user-1", 4)
	laptop := newTestClient("user-1", 4)
	hub.register(phone)
	hub.register(laptop)

	// SendToUser's envelope wraps this as json.RawMessage, which requires
	// already-valid JSON (production callers always pass an already-
	// json.Marshal'd payload — see chat/calls Service.pushEvent).
	hub.SendToUser("user-1", []byte(`{"msg":"hello"}`))

	waitForDelivery(t, phone.send, `{"msg":"hello"}`)
	waitForDelivery(t, laptop.send, `{"msg":"hello"}`)
}

func TestSendToUser_DoesNotLeakToOtherUsers(t *testing.T) {
	hub := newTestHub(t)

	recipient := newTestClient("user-1", 4)
	bystander := newTestClient("user-2", 4)
	hub.register(recipient)
	hub.register(bystander)

	hub.SendToUser("user-1", []byte(`{"msg":"private"}`))
	waitForDelivery(t, recipient.send, `{"msg":"private"}`)

	select {
	case got := <-bystander.send:
		t.Fatalf("message for user-1 was delivered to user-2: %q", got)
	case <-time.After(300 * time.Millisecond):
	}
}

// Sending to someone who isn't connected is a no-op, not a panic — this is
// the path taken whenever a call or message targets an offline user.
func TestSendToUser_OfflineUserIsNoOp(t *testing.T) {
	hub := newTestHub(t)
	hub.SendToUser("nobody-here", []byte(`{"msg":"hello"}`))
}

func TestIsOnline(t *testing.T) {
	hub := newTestHub(t)
	ctx := context.Background()

	if hub.IsOnline(ctx, "user-1") {
		t.Error("IsOnline reported true before any connection")
	}

	c := newTestClient("user-1", 1)
	hub.register(c)
	if !hub.IsOnline(ctx, "user-1") {
		t.Error("IsOnline reported false while connected")
	}

	hub.unregister(c)
	if hub.IsOnline(ctx, "user-1") {
		t.Error("IsOnline reported true after the only connection went away")
	}
}

// A user stays online while any one of their devices is still connected.
func TestIsOnline_MultipleDevices(t *testing.T) {
	hub := newTestHub(t)
	ctx := context.Background()

	phone := newTestClient("user-1", 1)
	laptop := newTestClient("user-1", 1)
	hub.register(phone)
	hub.register(laptop)

	hub.unregister(phone)
	if !hub.IsOnline(ctx, "user-1") {
		t.Fatal("user went offline while a second device was still connected")
	}

	hub.unregister(laptop)
	if hub.IsOnline(ctx, "user-1") {
		t.Fatal("user still online after every device disconnected")
	}
}

// A second instance's presence entry (simulated here by writing directly
// under a different instance ID) must keep a user online from this
// instance's point of view even with zero local connections — this is
// the entire point of moving presence into Redis (BUG-C08): a user
// connected only to instance B must still look online to instance A.
func TestIsOnline_ReflectsOtherInstances(t *testing.T) {
	hub := newTestHub(t)
	ctx := context.Background()

	if hub.IsOnline(ctx, "user-1") {
		t.Fatal("IsOnline reported true before any connection, on any instance")
	}

	future := float64(time.Now().Add(time.Minute).Unix())
	if err := hub.redis.ZAdd(ctx, presenceKey("user-1"), redis.Z{Score: future, Member: "some-other-instance"}).Err(); err != nil {
		t.Fatalf("failed to seed presence: %v", err)
	}

	if !hub.IsOnline(ctx, "user-1") {
		t.Fatal("IsOnline reported false for a user connected only to another instance")
	}
}

// A client whose buffer is full must be skipped rather than blocking the
// hub — one stuck consumer would otherwise stall delivery for everyone.
// Exercised directly against deliverLocal (what subscribeLoop calls per
// received envelope) rather than through the full SendToUser->Redis->
// subscribeLoop round trip, since that's where the full-buffer handling
// actually lives.
func TestDeliverLocal_FullBufferDoesNotBlockHub(t *testing.T) {
	hub := newTestHub(t)

	stuck := newTestClient("user-1", 1)
	hub.register(stuck)

	done := make(chan struct{})
	go func() {
		defer close(done)
		// Far more sends than the buffer can hold.
		for i := 0; i < 100; i++ {
			hub.deliverLocal("user-1", []byte("msg"))
		}
	}()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("deliverLocal blocked on a client with a full buffer")
	}
}

// The hub is written to from many goroutines (each connection's read loop,
// plus every publisher), so registration and delivery must be race-free.
// Meaningful under `go test -race`.
func TestHub_ConcurrentAccess(t *testing.T) {
	hub := newTestHub(t)
	ctx := context.Background()

	var wg sync.WaitGroup
	for i := 0; i < 25; i++ {
		wg.Add(3)

		go func() {
			defer wg.Done()
			c := newTestClient("user-1", 8)
			hub.register(c)
			hub.unregister(c)
		}()
		go func() {
			defer wg.Done()
			hub.SendToUser("user-1", []byte(`{"msg":"hi"}`))
		}()
		go func() {
			defer wg.Done()
			_ = hub.IsOnline(ctx, "user-1")
		}()
	}
	wg.Wait()
}
