// Package ratelimit provides a small Redis-backed fixed-window rate
// limiter (BUG-H10). Redis is already a required dependency of this
// project (pkg/redis), so this reuses that connection rather than
// pulling in a new library — and a Redis-backed counter, unlike an
// in-memory one, stays correct across the multiple API replicas/pods a
// real deployment would run.
package ratelimit

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// incrAndExpire atomically increments the counter at KEYS[1] and, only on
// the first increment (i.e. the window just started), sets its TTL to
// ARGV[1] milliseconds. Doing this in one round-trip via a Lua script
// avoids the race an INCR-then-EXPIRE pair would have (a key that's
// incremented but never gets its TTL set, if the process died between
// the two calls, would rate-limit forever).
var incrAndExpire = redis.NewScript(`
local count = redis.call("INCR", KEYS[1])
if count == 1 then
	redis.call("PEXPIRE", KEYS[1], ARGV[1])
end
local ttl = redis.call("PTTL", KEYS[1])
return {count, ttl}
`)

type Limiter struct {
	redis *redis.Client
}

func New(redisClient *redis.Client) *Limiter {
	return &Limiter{redis: redisClient}
}

// LimitExceededError is returned by Allow when the caller has hit the
// limit for the window; RetryAfter is how long until the window resets.
type LimitExceededError struct {
	RetryAfter time.Duration
}

func (e *LimitExceededError) Error() string {
	return fmt.Sprintf("rate limit exceeded, retry after %s", e.RetryAfter.Round(time.Second))
}

// Allow reports whether a request under key may proceed: up to limit
// requests are permitted within window, counted from the first request
// that opens the window (fixed window, not sliding — simple and cheap,
// and fine for abuse-prevention limits like these rather than
// billing-grade precision). Returns *LimitExceededError once the limit
// is hit for the rest of the current window.
func (l *Limiter) Allow(ctx context.Context, key string, limit int, window time.Duration) error {
	res, err := incrAndExpire.Run(ctx, l.redis, []string{key}, window.Milliseconds()).Result()
	if err != nil {
		return fmt.Errorf("ratelimit: %w", err)
	}

	vals, ok := res.([]interface{})
	if !ok || len(vals) != 2 {
		return fmt.Errorf("ratelimit: unexpected script result %v", res)
	}
	count, _ := vals[0].(int64)
	ttlMS, _ := vals[1].(int64)

	if count > int64(limit) {
		retryAfter := time.Duration(ttlMS) * time.Millisecond
		if retryAfter < 0 {
			// PTTL returns -1 if the key somehow has no TTL — fall back to
			// the full window rather than a nonsensical negative duration.
			retryAfter = window
		}
		return &LimitExceededError{RetryAfter: retryAfter}
	}
	return nil
}
