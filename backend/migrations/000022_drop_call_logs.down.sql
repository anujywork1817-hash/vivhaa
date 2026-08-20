-- Recreates call_logs with the same shape as 000017_create_call_logs.up.sql.
-- Data is NOT recoverable — this restores the empty table structure only.
CREATE TABLE call_logs (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_video         BOOLEAN NOT NULL DEFAULT FALSE,
    status           VARCHAR(16) NOT NULL DEFAULT 'missed', -- missed | answered | declined
    started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    answered_at      TIMESTAMPTZ,
    ended_at         TIMESTAMPTZ,

    CONSTRAINT call_logs_no_self CHECK (caller_user_id != receiver_user_id)
);

CREATE INDEX idx_call_logs_caller ON call_logs (caller_user_id, started_at DESC);
CREATE INDEX idx_call_logs_receiver ON call_logs (receiver_user_id, started_at DESC);
CREATE INDEX idx_call_logs_open ON call_logs (caller_user_id, receiver_user_id, started_at DESC)
    WHERE ended_at IS NULL;
