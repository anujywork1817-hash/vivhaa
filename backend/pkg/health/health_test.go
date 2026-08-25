package health

import (
	"context"
	"errors"
	"log/slog"
	"testing"
	"time"
)

// TestSnapshotDoesNotBlockOnSlowProbe proves the cache actually decouples
// GET /health's response time from live dependency latency: a probe that
// takes far longer than the old inline per-request check would tolerate
// must not make Snapshot (what the HTTP handler calls) slow, since
// Snapshot only ever reads the last cached result.
func TestSnapshotDoesNotBlockOnSlowProbe(t *testing.T) {
	slowProbe := func(ctx context.Context) error {
		select {
		case <-time.After(10 * time.Second):
			return nil
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	unreachableProbe := func(ctx context.Context) error {
		return errors.New("connection refused")
	}

	c := New(50*time.Millisecond, 500*time.Millisecond, 200*time.Millisecond, slog.Default(), map[string]Probe{
		"slow":        slowProbe,
		"unreachable": unreachableProbe,
	})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	c.Start(ctx) // runs one synchronous pass, then backgrounds the rest

	start := time.Now()
	snapshot := c.Snapshot()
	elapsed := time.Since(start)

	// The old inline design would have blocked here for up to the
	// probe's own timeout (3s in production); the cache must respond
	// in microseconds regardless of what the probes are doing.
	if elapsed > 50*time.Millisecond {
		t.Fatalf("Snapshot took %s, expected near-instant (cache read, no live network call)", elapsed)
	}

	if snapshot["unreachable"].OK {
		t.Fatalf("expected unreachable dependency to be reported as not-OK")
	}
}

// TestStaleResultReportedAsNotOK verifies the staleness safeguard: if the
// background prober itself stalls (or the check hasn't run recently
// enough), Snapshot must not keep serving an old "ok" forever.
func TestStaleResultReportedAsNotOK(t *testing.T) {
	healthyProbe := func(ctx context.Context) error { return nil }

	// staleAfter shorter than any real interval we'd run in production,
	// so the very first cached result is already stale by the time we
	// check it below.
	c := New(time.Hour, 10*time.Millisecond, time.Second, slog.Default(), map[string]Probe{
		"dep": healthyProbe,
	})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	c.Start(ctx)

	time.Sleep(20 * time.Millisecond)

	snapshot := c.Snapshot()
	if snapshot["dep"].OK {
		t.Fatalf("expected stale result to be reported as not-OK, got OK=true")
	}
	if !snapshot["dep"].Stale {
		t.Fatalf("expected Stale=true on an aged-out result")
	}
}

// TestPanicInProbeDoesNotStopChecker verifies a panicking probe is
// contained — it must not crash the process or stop other probes / future
// runs from completing.
func TestPanicInProbeDoesNotStopChecker(t *testing.T) {
	panicProbe := func(ctx context.Context) error {
		panic("boom")
	}
	okProbe := func(ctx context.Context) error { return nil }

	c := New(20*time.Millisecond, time.Second, time.Second, slog.Default(), map[string]Probe{
		"panics": panicProbe,
		"fine":   okProbe,
	})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Start's initial synchronous pass must survive the panic and return.
	c.Start(ctx)

	snapshot := c.Snapshot()
	if snapshot["panics"].OK {
		t.Fatalf("expected panicking probe to be reported as not-OK")
	}
	if !snapshot["fine"].OK {
		t.Fatalf("expected the other probe to still succeed despite a sibling panicking")
	}

	// Give the background ticker one more cycle to prove it kept running.
	time.Sleep(50 * time.Millisecond)
	snapshot = c.Snapshot()
	if snapshot["panics"].OK {
		t.Fatalf("expected panicking probe to still be reported as not-OK on a later cycle")
	}
}
