-- Call history. WebRTC signalling was previously relay-only and left no
-- trace, so there was no way to show a Calls list or tell a missed call
-- from one that was answered.
CREATE TABLE call_logs (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_video         BOOLEAN NOT NULL DEFAULT FALSE,

    -- Starts as 'missed' and is promoted on answer/decline, so a call that
    -- is never picked up (the client simply stops signalling) still ends
    -- up correctly classified without needing a timeout job.
    status           VARCHAR(16) NOT NULL DEFAULT 'missed', -- missed | answered | declined
    started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    answered_at      TIMESTAMPTZ,
    ended_at         TIMESTAMPTZ,

    CONSTRAINT call_logs_no_self CHECK (caller_user_id != receiver_user_id)
);

-- The Calls list is "every call involving me, newest first".
CREATE INDEX idx_call_logs_caller ON call_logs (caller_user_id, started_at DESC);
CREATE INDEX idx_call_logs_receiver ON call_logs (receiver_user_id, started_at DESC);

-- Answer/end signals carry no call id, so they're matched back to the most
-- recent still-open call between the pair.
CREATE INDEX idx_call_logs_open ON call_logs (caller_user_id, receiver_user_id, started_at DESC)
    WHERE ended_at IS NULL;
