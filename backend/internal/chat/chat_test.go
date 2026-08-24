package chat

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sync/atomic"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"matrimony-backend/internal/analytics"
	"matrimony-backend/internal/blocked"
	"matrimony-backend/internal/chatguard"
	"matrimony-backend/internal/interests"
	"matrimony-backend/internal/queue"
	"matrimony-backend/internal/websocket"
	"matrimony-backend/pkg/kafka"
	"matrimony-backend/pkg/testdb"
)

var testPhoneSeq int64

func uniquePhone(t *testing.T) string {
	t.Helper()
	n := atomic.AddInt64(&testPhoneSeq, 1)
	return fmt.Sprintf("+19257%06d%d", time.Now().Unix()%1000000, n%10)
}

// testDeps bundles a real Service against the test DB with the
// collaborator repos tests need to set up fixtures (a mutual match, a
// block) directly, without going through the interests/blocked HTTP
// handlers.
//
// profilesSvc/subsSvc are left nil: neither SendMessage nor RequestContact
// (the gating logic under test here) touches them — only RespondContact's
// accept path does, which needs a working profiles.Service (S3 uploader,
// etc.) to test meaningfully and is out of scope for this pass.
//
// The publisher is real but points at an unreachable broker address —
// chat.Service always swallows publish errors, so this is a safe no-op
// stand-in without needing a live Kafka. The Hub is backed by miniredis,
// the same pattern internal/websocket/hub_test.go already uses.
type testDeps struct {
	svc           *Service
	pool          *pgxpool.Pool
	interestsRepo *interests.Repository
	blockedRepo   *blocked.Repository
}

func newTestDeps(t *testing.T) *testDeps {
	t.Helper()
	pool := testdb.Connect(t)

	mr := miniredis.RunT(t)
	redisClient := redis.NewClient(&redis.Options{Addr: mr.Addr(), Protocol: 2})
	t.Cleanup(func() { _ = redisClient.Close() })
	hub := websocket.NewHub(context.Background(), redisClient, slog.Default())

	repo := NewRepository(pool)
	interestsRepo := interests.NewRepository(pool)
	blockedRepo := blocked.NewRepository(pool)
	analyticsSvc := analytics.NewService(analytics.NewRepository(pool))
	publisher := queue.NewPublisher(kafka.NewProducer([]string{"127.0.0.1:1"}))

	guard := chatguard.NewEngine(chatguard.Config{Enabled: true})
	svc := NewService(repo, interestsRepo, blockedRepo, nil, publisher, nil, analyticsSvc, hub, guard, AbuseConfig{RestrictThreshold: 3, RestrictDuration: time.Hour, ReviewThreshold: 6})
	return &testDeps{svc: svc, pool: pool, interestsRepo: interestsRepo, blockedRepo: blockedRepo}
}

// mustMutualMatch creates and accepts an interest between a and b — the
// same "IsAccepted" state SendMessage/RequestContact gate on.
func mustMutualMatch(t *testing.T, deps *testDeps, a, b string) {
	t.Helper()
	ctx := context.Background()
	i, err := deps.interestsRepo.Create(ctx, a, b)
	if err != nil {
		t.Fatalf("interests.Create: %v", err)
	}
	if _, err := deps.interestsRepo.UpdateStatus(ctx, i.ID, "accepted"); err != nil {
		t.Fatalf("interests.UpdateStatus: %v", err)
	}
}

func TestSendMessage_NoMutualInterest_ReturnsErrChatNotAllowed(t *testing.T) {
	deps := newTestDeps(t)
	userA := testdb.NewUser(t, deps.pool, uniquePhone(t))
	userB := testdb.NewUser(t, deps.pool, uniquePhone(t))

	_, err := deps.svc.SendMessage(context.Background(), userA, userB, "hi there", nil)
	if !errors.Is(err, ErrChatNotAllowed) {
		t.Errorf("SendMessage() between unmatched users = %v, want ErrChatNotAllowed", err)
	}
}

func TestSendMessage_MutualInterest_Succeeds(t *testing.T) {
	deps := newTestDeps(t)
	userA := testdb.NewUser(t, deps.pool, uniquePhone(t))
	userB := testdb.NewUser(t, deps.pool, uniquePhone(t))
	mustMutualMatch(t, deps, userA, userB)

	resp, err := deps.svc.SendMessage(context.Background(), userA, userB, "hello!", nil)
	if err != nil {
		t.Fatalf("SendMessage() between matched users: %v", err)
	}
	if resp.Body != "hello!" || resp.SenderUserID != userA || resp.ReceiverUserID != userB {
		t.Errorf("SendMessage() response = %+v, unexpected", resp)
	}
}

// TestSendMessage_DeletedMatch_ReturnsErrChatNotAllowed is a regression
// test for BUG-H09: deleting (unmatching) an accepted interest must
// revoke chat access immediately, not leave it open because IsAccepted
// used to ignore deleted_at.
func TestSendMessage_DeletedMatch_ReturnsErrChatNotAllowed(t *testing.T) {
	deps := newTestDeps(t)
	userA := testdb.NewUser(t, deps.pool, uniquePhone(t))
	userB := testdb.NewUser(t, deps.pool, uniquePhone(t))
	ctx := context.Background()

	i, err := deps.interestsRepo.Create(ctx, userA, userB)
	if err != nil {
		t.Fatalf("interests.Create: %v", err)
	}
	if _, err := deps.interestsRepo.UpdateStatus(ctx, i.ID, "accepted"); err != nil {
		t.Fatalf("interests.UpdateStatus: %v", err)
	}

	// Sanity: chat works while the match is live.
	if _, err := deps.svc.SendMessage(ctx, userA, userB, "before unmatch", nil); err != nil {
		t.Fatalf("SendMessage() before unmatch: %v", err)
	}

	if err := deps.interestsRepo.Delete(ctx, i.ID, userA); err != nil {
		t.Fatalf("interests.Delete (unmatch): %v", err)
	}

	_, err = deps.svc.SendMessage(ctx, userA, userB, "after unmatch", nil)
	if !errors.Is(err, ErrChatNotAllowed) {
		t.Errorf("SendMessage() after unmatch = %v, want ErrChatNotAllowed", err)
	}
}

func TestSendMessage_BlockedUser_ReturnsErrBlocked(t *testing.T) {
	deps := newTestDeps(t)
	userA := testdb.NewUser(t, deps.pool, uniquePhone(t))
	userB := testdb.NewUser(t, deps.pool, uniquePhone(t))
	ctx := context.Background()

	mustMutualMatch(t, deps, userA, userB)
	if _, err := deps.blockedRepo.Create(ctx, userB, userA); err != nil {
		t.Fatalf("blocked.Create: %v", err)
	}

	_, err := deps.svc.SendMessage(ctx, userA, userB, "can you see this?", nil)
	if !errors.Is(err, ErrBlocked) {
		t.Errorf("SendMessage() to a user who blocked the sender = %v, want ErrBlocked", err)
	}
}

func TestSendMessage_SelfMessage_ReturnsErrSelfMessage(t *testing.T) {
	deps := newTestDeps(t)
	userA := testdb.NewUser(t, deps.pool, uniquePhone(t))

	_, err := deps.svc.SendMessage(context.Background(), userA, userA, "hi me", nil)
	if !errors.Is(err, ErrSelfMessage) {
		t.Errorf("SendMessage() to self = %v, want ErrSelfMessage", err)
	}
}

func TestRequestContact_NoMutualInterest_ReturnsErrChatNotAllowed(t *testing.T) {
	deps := newTestDeps(t)
	userA := testdb.NewUser(t, deps.pool, uniquePhone(t))
	userB := testdb.NewUser(t, deps.pool, uniquePhone(t))

	_, err := deps.svc.RequestContact(context.Background(), userA, userB)
	if !errors.Is(err, ErrChatNotAllowed) {
		t.Errorf("RequestContact() between unmatched users = %v, want ErrChatNotAllowed", err)
	}
}

func TestRequestContact_MutualInterest_CreatesPendingRequest(t *testing.T) {
	deps := newTestDeps(t)
	userA := testdb.NewUser(t, deps.pool, uniquePhone(t))
	userB := testdb.NewUser(t, deps.pool, uniquePhone(t))
	mustMutualMatch(t, deps, userA, userB)

	resp, err := deps.svc.RequestContact(context.Background(), userA, userB)
	if err != nil {
		t.Fatalf("RequestContact() between matched users: %v", err)
	}
	if resp.Kind != MessageKindContactRequest {
		t.Errorf("RequestContact() kind = %q, want %q", resp.Kind, MessageKindContactRequest)
	}
}

func TestRequestContact_DuplicatePending_ReturnsErrContactRequestPending(t *testing.T) {
	deps := newTestDeps(t)
	userA := testdb.NewUser(t, deps.pool, uniquePhone(t))
	userB := testdb.NewUser(t, deps.pool, uniquePhone(t))
	mustMutualMatch(t, deps, userA, userB)
	ctx := context.Background()

	if _, err := deps.svc.RequestContact(ctx, userA, userB); err != nil {
		t.Fatalf("first RequestContact(): %v", err)
	}
	_, err := deps.svc.RequestContact(ctx, userA, userB)
	if !errors.Is(err, ErrContactRequestPending) {
		t.Errorf("second RequestContact() while one is pending = %v, want ErrContactRequestPending", err)
	}
}

// TestSendMessage_ContactInfoBlocked_NotPersisted is the core Phase 17/22
// guarantee: a phone number sent as plain text is rejected server-side
// and never written to chat_messages, even though the exact same call
// path (SendMessage) succeeds for ordinary text once matched.
func TestSendMessage_ContactInfoBlocked_NotPersisted(t *testing.T) {
	deps := newTestDeps(t)
	userA := testdb.NewUser(t, deps.pool, uniquePhone(t))
	userB := testdb.NewUser(t, deps.pool, uniquePhone(t))
	mustMutualMatch(t, deps, userA, userB)
	ctx := context.Background()

	_, err := deps.svc.SendMessage(ctx, userA, userB, "call me on 9876543210", nil)
	if !errors.Is(err, ErrContactInfoBlocked) {
		t.Fatalf("SendMessage() with a phone number = %v, want ErrContactInfoBlocked", err)
	}

	history, err := deps.svc.repo.History(ctx, userA, userB, 50)
	if err != nil {
		t.Fatalf("History(): %v", err)
	}
	if len(history) != 0 {
		t.Errorf("expected no persisted messages after a blocked send, got %d: %+v", len(history), history)
	}
}

// TestSendMessage_RepeatedViolations_Restricted exercises Phase 14's
// escalation: once violationCount crosses RestrictThreshold, further
// sends — even benign ones — are rejected with ErrChatRestricted until
// the restriction expires.
func TestSendMessage_RepeatedViolations_Restricted(t *testing.T) {
	deps := newTestDeps(t)
	userA := testdb.NewUser(t, deps.pool, uniquePhone(t))
	userB := testdb.NewUser(t, deps.pool, uniquePhone(t))
	mustMutualMatch(t, deps, userA, userB)
	ctx := context.Background()

	for i := 0; i < 3; i++ {
		_, err := deps.svc.SendMessage(ctx, userA, userB, "email me at name@example.com", nil)
		if !errors.Is(err, ErrContactInfoBlocked) {
			t.Fatalf("violation #%d = %v, want ErrContactInfoBlocked", i+1, err)
		}
	}

	_, err := deps.svc.SendMessage(ctx, userA, userB, "hello, totally normal message", nil)
	if !errors.Is(err, ErrChatRestricted) {
		t.Errorf("SendMessage() after crossing RestrictThreshold = %v, want ErrChatRestricted", err)
	}
}

// TestSendMessage_ContactSharedFlow_BypassesModeration confirms the
// explicit mutual-consent flow (RequestContact -> RespondContact) is
// unaffected by moderation — it's the one sanctioned way a real number
// reaches the other participant.
func TestSendMessage_ContactSharedFlow_BypassesModeration(t *testing.T) {
	deps := newTestDeps(t)
	userA := testdb.NewUser(t, deps.pool, uniquePhone(t))
	userB := testdb.NewUser(t, deps.pool, uniquePhone(t))
	mustMutualMatch(t, deps, userA, userB)
	ctx := context.Background()

	req, err := deps.svc.RequestContact(ctx, userA, userB)
	if err != nil {
		t.Fatalf("RequestContact(): %v", err)
	}
	if _, err := deps.svc.RespondContact(ctx, userB, req.ID, true); err != nil {
		t.Fatalf("RespondContact(accept): %v", err)
	}
}
