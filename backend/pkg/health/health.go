// Package health runs dependency reachability probes (DB, Redis,
// Elasticsearch, Kafka, storage buckets) on a background interval and
// serves the last result from memory, so the HTTP /health handler never
// makes a live network call in the request path.
//
// This replaces an earlier version of /health that ran all probes inline
// per-request: under a 1000-VU load test that hit /health every
// iteration, five synchronous dependency checks (each within a shared
// 3-second timeout) measurably degraded latency and throughput for the
// whole service, not just /health itself (p95 48ms -> 382ms,
// ~1300req/s -> ~1000req/s). Probing on a fixed interval in the
// background and serving cached results decouples /health's response
// time from live dependency latency entirely.
package health

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"
)

// Probe checks one dependency and returns a non-nil error if it's
// unreachable. It's given a context already scoped to a per-probe timeout.
type Probe func(ctx context.Context) error

type status struct {
	ok          bool
	lastChecked time.Time
	err         error
}

// Result is one dependency's cached status, safe to read after Snapshot.
type Result struct {
	OK      bool
	Stale   bool
	Message string
}

// Checker runs a fixed set of named probes on an interval and serves the
// latest results from memory.
type Checker struct {
	probes       map[string]Probe
	interval     time.Duration
	staleAfter   time.Duration
	probeTimeout time.Duration
	log          *slog.Logger

	mu      sync.RWMutex
	results map[string]status
}

// New builds a Checker. interval is how often probes run in the
// background; staleAfter is how long a probe's last successful run can
// age before Snapshot reports it as stale (protects against serving
// arbitrarily old "ok" data forever if the background loop itself has
// stalled); probeTimeout bounds each individual probe call.
func New(interval, staleAfter, probeTimeout time.Duration, log *slog.Logger, probes map[string]Probe) *Checker {
	results := make(map[string]status, len(probes))
	for name := range probes {
		// Unknown until the first run completes, but not yet "stale" —
		// Run() does an initial synchronous pass before Start returns.
		results[name] = status{lastChecked: time.Now()}
	}
	return &Checker{
		probes:       probes,
		interval:     interval,
		staleAfter:   staleAfter,
		probeTimeout: probeTimeout,
		log:          log,
		results:      results,
	}
}

// Start runs one synchronous probe pass (so Snapshot has real data
// immediately at startup) and then launches the background loop. Stops
// when ctx is cancelled.
func (c *Checker) Start(ctx context.Context) {
	c.runOnce(ctx)
	go func() {
		ticker := time.NewTicker(c.interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				c.runOnce(ctx)
			}
		}
	}()
}

func (c *Checker) runOnce(ctx context.Context) {
	for name, probe := range c.probes {
		name, probe := name, probe
		func() {
			// A probe panicking (e.g. a client library bug) must not take
			// down the background loop, let alone the process — log it
			// and keep retrying on the next interval.
			defer func() {
				if r := recover(); r != nil {
					c.record(name, fmt.Errorf("probe panicked: %v", r))
					c.log.Error("health probe panicked", "dependency", name, "panic", r)
				}
			}()
			probeCtx, cancel := context.WithTimeout(ctx, c.probeTimeout)
			defer cancel()
			err := probe(probeCtx)
			c.record(name, err)
			if err != nil {
				c.log.Error("health probe failed", "dependency", name, "error", err)
			}
		}()
	}
}

func (c *Checker) record(name string, err error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.results[name] = status{ok: err == nil, lastChecked: time.Now(), err: err}
}

// Snapshot returns the current cached view of every dependency —
// read-only, no network calls, safe to call from every request.
func (c *Checker) Snapshot() map[string]Result {
	c.mu.RLock()
	defer c.mu.RUnlock()

	out := make(map[string]Result, len(c.results))
	for name, s := range c.results {
		stale := time.Since(s.lastChecked) > c.staleAfter
		r := Result{OK: s.ok && !stale, Stale: stale}
		switch {
		case stale:
			r.Message = fmt.Sprintf("stale: last checked %s ago", time.Since(s.lastChecked).Round(time.Second))
		case s.err != nil:
			r.Message = s.err.Error()
		default:
			r.Message = "ok"
		}
		out[name] = r
	}
	return out
}
