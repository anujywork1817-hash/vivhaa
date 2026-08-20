package subscriptions

import (
	"context"
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"matrimony-backend/pkg/testdb"
)

var testPhoneSeq int64

func uniquePhone(t *testing.T) string {
	t.Helper()
	n := atomic.AddInt64(&testPhoneSeq, 1)
	return fmt.Sprintf("+19259%06d%d", time.Now().Unix()%1000000, n%10)
}

type testEnv struct {
	svc    *Service
	repo   *Repository
	pool   *pgxpool.Pool
	userID string
}

func newTestEnv(t *testing.T) testEnv {
	t.Helper()
	pool := testdb.Connect(t)
	repo := NewRepository(pool)
	userID := testdb.NewUser(t, pool, uniquePhone(t))
	return testEnv{svc: NewService(repo), repo: repo, pool: pool, userID: userID}
}

// activatePlan mirrors what payments.Service.finalizeCapturedPayment does
// (CreatePending then Activate inside a transaction) — GetMine/HasFeature
// only ever see a subscription in its post-activation shape in production,
// so tests exercise that real path rather than poking status='active'
// directly into the row.
func (e testEnv) activatePlan(t *testing.T, planCode string) {
	t.Helper()
	ctx := context.Background()

	plan, err := e.repo.GetPlanByCode(ctx, planCode)
	if err != nil {
		t.Fatalf("GetPlanByCode(%s): %v", planCode, err)
	}
	sub, err := e.repo.CreatePending(ctx, e.userID, plan.ID)
	if err != nil {
		t.Fatalf("CreatePending: %v", err)
	}
	tx, err := e.pool.Begin(ctx)
	if err != nil {
		t.Fatalf("Begin: %v", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := e.repo.Activate(ctx, tx, sub.ID, plan.DurationDays); err != nil {
		t.Fatalf("Activate: %v", err)
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatalf("Commit: %v", err)
	}
}

func TestGetMine_NoSubscription_FallsBackToFreePlan(t *testing.T) {
	env := newTestEnv(t)

	resp, err := env.svc.GetMine(context.Background(), env.userID)
	if err != nil {
		t.Fatalf("GetMine() for a user with no subscription: %v", err)
	}
	if resp.PlanCode != "free" || resp.Status != "active" {
		t.Errorf("GetMine() = %+v, want plan_code=free status=active", resp)
	}
}

func TestHasFeature_NoSubscription_UsesFreePlanFeatures(t *testing.T) {
	env := newTestEnv(t)

	has, err := env.svc.HasFeature(context.Background(), env.userID, "view_contact")
	if err != nil {
		t.Fatalf("HasFeature() error: %v", err)
	}
	if has {
		t.Error("HasFeature(view_contact) for a free-tier user = true, want false (free plan has no features)")
	}
}

func TestGetMine_ActiveSubscription_ReturnsPlanDetails(t *testing.T) {
	env := newTestEnv(t)
	env.activatePlan(t, "premium_monthly")

	resp, err := env.svc.GetMine(context.Background(), env.userID)
	if err != nil {
		t.Fatalf("GetMine() after activation: %v", err)
	}
	if resp.PlanCode != "premium_monthly" || resp.Status != "active" {
		t.Errorf("GetMine() = %+v, want plan_code=premium_monthly status=active", resp)
	}
	if resp.EndsAt == nil {
		t.Error("GetMine() for an active paid plan should report an ends_at")
	}
}

func TestHasFeature_ActiveSubscriber_UsesTheirPlanFeatures(t *testing.T) {
	env := newTestEnv(t)
	env.activatePlan(t, "premium_monthly")

	has, err := env.svc.HasFeature(context.Background(), env.userID, "view_contact")
	if err != nil {
		t.Fatalf("HasFeature() error: %v", err)
	}
	if !has {
		t.Error("HasFeature(view_contact) for an active premium subscriber = false, want true")
	}
}

func TestHasFeature_UnknownFeature_ReturnsFalse(t *testing.T) {
	env := newTestEnv(t)
	env.activatePlan(t, "premium_monthly")

	has, err := env.svc.HasFeature(context.Background(), env.userID, "not_a_real_feature")
	if err != nil {
		t.Fatalf("HasFeature() error: %v", err)
	}
	if has {
		t.Error("HasFeature() for a nonexistent feature key = true, want false")
	}
}
