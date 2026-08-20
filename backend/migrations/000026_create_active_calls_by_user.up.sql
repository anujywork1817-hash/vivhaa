-- Cross-instance replacement for calls.Service's old in-memory
-- userToCall map (BUG-C08). With more than one API replica, "is this user
-- already in a call" can no longer be answered by a local Go map — the
-- initiate for one call and the accept for another could land on
-- different instances. user_id as the primary key gives Postgres itself
-- the same "only one active call per user" guarantee the in-memory map's
-- mutex used to give locally: inserting a second row for a user already
-- present is a unique-violation, translated by the repository into the
-- same "busy" signal the old map produced.
--
-- One row per participant per active call (so a call has two rows, one
-- for caller and one for callee) — deleted when the call ends, by
-- whichever path ends it (accept/reject/timeout/hangup/disconnect).
CREATE TABLE active_calls_by_user (
    user_id  UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    call_id  UUID NOT NULL REFERENCES call_sessions(id) ON DELETE CASCADE
);

CREATE INDEX idx_active_calls_by_user_call_id ON active_calls_by_user (call_id);
