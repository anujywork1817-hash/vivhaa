package interests

import (
	"context"
	"errors"
	"fmt"
	"net"
	"sync/atomic"
	"testing"
	"time"

	"matrimony-backend/internal/analytics"
	"matrimony-backend/internal/blocked"
	"matrimony-backend/internal/profiles"
	"matrimony-backend/internal/queue"
	"matrimony-backend/pkg/kafka"
	"matrimony-backend/pkg/testdb"
)

const kafkaTestBroker = "localhost:59092"

// requireKafka skips the calling test if the dev Kafka broker isn't
// reachable — only Remind() actually needs a working publish (it returns
// PublishNotificationDispatch's error directly, unlike every other method
// in this package), so this is called from just that one test rather than
// gating the whole file.
func requireKafka(t *testing.T) {
	t.Helper()
	conn, err := net.DialTimeout("tcp", kafkaTestBroker, 2*time.Second)
	if err != nil {
		t.Skipf("skipping: dev Kafka broker not reachable at %s: %v", kafkaTestBroker, err)
	}
	_ = conn.Close()
}

var testPhoneSeq int64

func uniquePhone(t *testing.T) string {
	t.Helper()
	n := atomic.AddInt64(&testPhoneSeq, 1)
	return fmt.Sprintf("+19258%06d%d", time.Now().Unix()%1000000, n%10)
}

func newTestService(t *testing.T) *Service {
	t.Helper()
	pool := testdb.Connect(t)

	repo := NewRepository(pool)
	profilesRepo := profiles.NewRepository(pool)
	blockedRepo := blocked.NewRepository(pool)
	analyticsSvc := analytics.NewService(analytics.NewRepository(pool))
	// Unlike chat.Service (which swallows publish errors), Remind()
	// returns PublishNotificationDispatch's error directly — a fake
	// unreachable broker would make every successful-Remind test fail on
	// the publish step alone, so this needs the real dev Kafka broker
	// (docker-compose's kafka service, external listener) rather than the
	// unreachable-address trick chat/auth's tests use.
	publisher := queue.NewPublisher(kafka.NewProducer([]string{"localhost:59092"}))

	return NewService(repo, profilesRepo, blockedRepo, publisher, analyticsSvc)
}

func newTestUser(t *testing.T) string {
	t.Helper()
	pool := testdb.Connect(t)
	return testdb.NewUser(t, pool, uniquePhone(t))
}

// mustCreateInterest creates a pending interest directly via the
// repository, bypassing Express() (which needs a real profile row) —
// interests.Service.Accept/Decline/Delete/Remind only ever need the
// interests row itself.
func mustCreateInterest(t *testing.T, svc *Service, sender, receiver string) Interest {
	t.Helper()
	i, err := svc.repo.Create(context.Background(), sender, receiver)
	if err != nil {
		t.Fatalf("repo.Create: %v", err)
	}
	return i
}

func TestAccept_ByReceiver_Succeeds(t *testing.T) {
	svc := newTestService(t)
	sender, receiver := newTestUser(t), newTestUser(t)
	i := mustCreateInterest(t, svc, sender, receiver)

	resp, err := svc.Accept(context.Background(), receiver, i.ID)
	if err != nil {
		t.Fatalf("Accept() by receiver: %v", err)
	}
	if resp.Status != "accepted" {
		t.Errorf("Accept() status = %q, want accepted", resp.Status)
	}
}

func TestAccept_ByNonReceiver_ReturnsErrForbidden(t *testing.T) {
	svc := newTestService(t)
	sender, receiver := newTestUser(t), newTestUser(t)
	bystander := newTestUser(t)
	i := mustCreateInterest(t, svc, sender, receiver)

	_, err := svc.Accept(context.Background(), bystander, i.ID)
	if !errors.Is(err, ErrForbidden) {
		t.Errorf("Accept() by a non-recipient = %v, want ErrForbidden", err)
	}
}

func TestAccept_BySender_ReturnsErrForbidden(t *testing.T) {
	// The sender of an interest is not its recipient — only the receiver
	// may accept/decline it.
	svc := newTestService(t)
	sender, receiver := newTestUser(t), newTestUser(t)
	i := mustCreateInterest(t, svc, sender, receiver)

	_, err := svc.Accept(context.Background(), sender, i.ID)
	if !errors.Is(err, ErrForbidden) {
		t.Errorf("Accept() by the sender = %v, want ErrForbidden", err)
	}
}

func TestAccept_AlreadyResponded_ReturnsErrAlreadyResponded(t *testing.T) {
	svc := newTestService(t)
	sender, receiver := newTestUser(t), newTestUser(t)
	i := mustCreateInterest(t, svc, sender, receiver)
	ctx := context.Background()

	if _, err := svc.Accept(ctx, receiver, i.ID); err != nil {
		t.Fatalf("first Accept(): %v", err)
	}
	_, err := svc.Accept(ctx, receiver, i.ID)
	if !errors.Is(err, ErrAlreadyResponded) {
		t.Errorf("Accept() on an already-accepted interest = %v, want ErrAlreadyResponded", err)
	}
}

func TestDecline_ByReceiver_Succeeds(t *testing.T) {
	svc := newTestService(t)
	sender, receiver := newTestUser(t), newTestUser(t)
	i := mustCreateInterest(t, svc, sender, receiver)

	resp, err := svc.Decline(context.Background(), receiver, i.ID)
	if err != nil {
		t.Fatalf("Decline() by receiver: %v", err)
	}
	if resp.Status != "declined" {
		t.Errorf("Decline() status = %q, want declined", resp.Status)
	}
}

// TestAccept_DeletedInterest_ReturnsErrNotFound is a regression test for
// BUG-H09: a soft-deleted interest must not still be acceptable/
// declinable — GetByID (which Accept/Decline both call through respond())
// must filter deleted_at.
func TestAccept_DeletedInterest_ReturnsErrNotFound(t *testing.T) {
	svc := newTestService(t)
	sender, receiver := newTestUser(t), newTestUser(t)
	i := mustCreateInterest(t, svc, sender, receiver)
	ctx := context.Background()

	if err := svc.Delete(ctx, sender, i.ID); err != nil {
		t.Fatalf("Delete(): %v", err)
	}

	_, err := svc.Accept(ctx, receiver, i.ID)
	if !errors.Is(err, ErrNotFound) {
		t.Errorf("Accept() on a deleted interest = %v, want ErrNotFound", err)
	}
}

func TestDelete_ByEitherParty_Succeeds(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()

	sender, receiver := newTestUser(t), newTestUser(t)
	i1 := mustCreateInterest(t, svc, sender, receiver)
	if err := svc.Delete(ctx, sender, i1.ID); err != nil {
		t.Errorf("Delete() by sender: %v", err)
	}

	i2 := mustCreateInterest(t, svc, sender, receiver)
	if err := svc.Delete(ctx, receiver, i2.ID); err != nil {
		t.Errorf("Delete() by receiver: %v", err)
	}
}

func TestDelete_ByBystander_ReturnsErrNotFound(t *testing.T) {
	// Delete's repo query scopes to "sender_user_id = $2 OR
	// receiver_user_id = $2", so a non-party deleting someone else's
	// interest must not succeed (and must not reveal whether the id
	// exists at all — same error as a bad id).
	svc := newTestService(t)
	sender, receiver := newTestUser(t), newTestUser(t)
	bystander := newTestUser(t)
	i := mustCreateInterest(t, svc, sender, receiver)

	err := svc.Delete(context.Background(), bystander, i.ID)
	if !errors.Is(err, ErrNotFound) {
		t.Errorf("Delete() by a non-party = %v, want ErrNotFound", err)
	}
}

func TestDelete_Idempotent_SecondDeleteReturnsErrNotFound(t *testing.T) {
	svc := newTestService(t)
	sender, receiver := newTestUser(t), newTestUser(t)
	i := mustCreateInterest(t, svc, sender, receiver)
	ctx := context.Background()

	if err := svc.Delete(ctx, sender, i.ID); err != nil {
		t.Fatalf("first Delete(): %v", err)
	}
	err := svc.Delete(ctx, sender, i.ID)
	if !errors.Is(err, ErrNotFound) {
		t.Errorf("second Delete() on an already-deleted interest = %v, want ErrNotFound", err)
	}
}

func TestRemind_Pending_Succeeds(t *testing.T) {
	requireKafka(t)
	svc := newTestService(t)
	sender, receiver := newTestUser(t), newTestUser(t)
	i := mustCreateInterest(t, svc, sender, receiver)

	if err := svc.Remind(context.Background(), sender, i.ID); err != nil {
		t.Errorf("Remind() on a pending interest by its sender: %v", err)
	}
}

func TestRemind_ByNonSender_ReturnsErrNotFound(t *testing.T) {
	svc := newTestService(t)
	sender, receiver := newTestUser(t), newTestUser(t)
	i := mustCreateInterest(t, svc, sender, receiver)

	err := svc.Remind(context.Background(), receiver, i.ID)
	if !errors.Is(err, ErrNotFound) {
		t.Errorf("Remind() by the receiver (not sender) = %v, want ErrNotFound", err)
	}
}

func TestRemind_AlreadyAccepted_ReturnsErrAlreadyResponded(t *testing.T) {
	svc := newTestService(t)
	sender, receiver := newTestUser(t), newTestUser(t)
	i := mustCreateInterest(t, svc, sender, receiver)
	ctx := context.Background()

	if _, err := svc.Accept(ctx, receiver, i.ID); err != nil {
		t.Fatalf("Accept(): %v", err)
	}

	err := svc.Remind(ctx, sender, i.ID)
	if !errors.Is(err, ErrAlreadyResponded) {
		t.Errorf("Remind() on an already-accepted interest = %v, want ErrAlreadyResponded", err)
	}
}

// TestRemind_DeletedInterest_ReturnsErrNotFound is the Remind half of the
// BUG-H09 regression: a withdrawn/deleted interest must not still be
// remindable.
func TestRemind_DeletedInterest_ReturnsErrNotFound(t *testing.T) {
	svc := newTestService(t)
	sender, receiver := newTestUser(t), newTestUser(t)
	i := mustCreateInterest(t, svc, sender, receiver)
	ctx := context.Background()

	if err := svc.Delete(ctx, sender, i.ID); err != nil {
		t.Fatalf("Delete(): %v", err)
	}

	err := svc.Remind(ctx, sender, i.ID)
	if !errors.Is(err, ErrNotFound) {
		t.Errorf("Remind() on a deleted interest = %v, want ErrNotFound", err)
	}
}
