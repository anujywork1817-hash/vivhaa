-- Video/voice call sessions: one row per call attempt, created when the
-- callee actually receives the offer (not on every initiate — see
-- internal/calls.Service.Initiate, which rejects busy/blocked/unconnected
-- callers before ever creating a row) and updated as the call progresses.
-- id doubles as the WebRTC signaling correlation ID (the "call ID" used in
-- call:accept/reject/ice-candidate/end messages), so the frontend never has
-- to track two separate identifiers for the same call.
CREATE TABLE call_sessions (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    callee_user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- initiated: ringing, not yet answered
    -- ongoing:   answered, currently connected
    -- completed: was ongoing, ended normally by either side
    -- missed:    never answered (30s timeout) or caller cancelled first
    -- rejected:  callee explicitly declined
    -- failed:    connection/ICE failure after being ongoing
    status           VARCHAR(16) NOT NULL DEFAULT 'initiated',
    started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    connected_at     TIMESTAMPTZ,
    ended_at         TIMESTAMPTZ,
    duration_seconds INT,
    -- caller_ended | callee_ended | rejected | timeout | caller_cancelled |
    -- connection_failed | busy
    end_reason       VARCHAR(24),

    CONSTRAINT call_sessions_no_self CHECK (caller_user_id != callee_user_id),
    CONSTRAINT call_sessions_status CHECK (
        status IN ('initiated', 'ongoing', 'completed', 'missed', 'rejected', 'failed')
    )
);

-- caller_id/callee_id/started_at per the admin call-history query pattern
-- (filter by participant, sort/filter by date range) — mirrors how
-- idx_call_logs_caller/idx_call_logs_receiver were indexed before.
CREATE INDEX idx_call_sessions_caller ON call_sessions (caller_user_id, started_at DESC);
CREATE INDEX idx_call_sessions_callee ON call_sessions (callee_user_id, started_at DESC);
CREATE INDEX idx_call_sessions_started_at ON call_sessions (started_at DESC);
