// Package testdb provides the integration-test database harness used by
// the auth/payments/chat/interests/subscriptions test suites (Phase 9).
//
// Nothing in this codebase's repository layer takes an interface — every
// Service holds a concrete *Repository wrapping *pgxpool.Pool directly
// (see internal/auth, internal/payments, internal/chat, etc.) — so there
// is no seam to fake the database through. Rather than refactor five
// packages to introduce one, these tests run against a real Postgres:
// a dedicated "myapp_test" database (same instance as the dev
// docker-compose Postgres, migrated the same way — see
// migrations/README below), reachable at TEST_DATABASE_URL or the
// default dev docker-compose port. Tests that can't reach it skip
// instead of failing, so this suite doesn't break CI/machines that
// haven't set the test DB up.
//
// Setup (one-time, same Postgres container docker-compose already runs):
//
//	docker compose exec -T postgres psql -U postgres -c "CREATE DATABASE myapp_test;"
//	docker run --rm --network matrimony_backend_default -v "<repo>/migrations:/migrations" \
//	  migrate/migrate:v4.17.1 -path=/migrations \
//	  -database "postgres://postgres:postgres@postgres:5432/myapp_test?sslmode=disable" up
package testdb

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

const defaultTestDSN = "postgres://postgres:postgres@localhost:55432/myapp_test?sslmode=disable"

// Connect returns a pool against the integration-test database, or skips
// the calling test if it can't be reached.
func Connect(t *testing.T) *pgxpool.Pool {
	t.Helper()

	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = defaultTestDSN
	}

	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Skipf("skipping integration test: cannot create pool for %s: %v", dsn, err)
	}
	if err := pool.Ping(context.Background()); err != nil {
		pool.Close()
		t.Skipf("skipping integration test: cannot reach test database at %s: %v\n"+
			"start it with `docker compose up -d postgres` and set up myapp_test — see pkg/testdb/testdb.go", dsn, err)
	}

	t.Cleanup(pool.Close)
	return pool
}

// NewUser inserts a throwaway active, verified user for a test and
// registers a cleanup that deletes it — every table that references
// users(id) does so with ON DELETE CASCADE (interests, chat_messages,
// payments, subscriptions, etc. — see migrations/), so this one delete
// cleans up everything a test created off the back of this user too,
// without needing per-table teardown in every test.
func NewUser(t *testing.T, pool *pgxpool.Pool, phone string) string {
	t.Helper()
	ctx := context.Background()

	var userID string
	err := pool.QueryRow(ctx, `
		INSERT INTO users (phone, status, phone_verified)
		VALUES ($1, 'active', true)
		RETURNING id`, phone).Scan(&userID)
	if err != nil {
		t.Fatalf("testdb.NewUser: %v", err)
	}

	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, userID)
	})
	return userID
}
