-- Server-side chat contact-info moderation: an event log for every
-- moderation decision (never stores raw phone/email content -- see
-- internal/chatguard's doc comments) and an escalating per-user
-- restriction record driven by repeated violations.

CREATE TABLE moderation_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    partner_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    message_id      UUID REFERENCES chat_messages(id) ON DELETE SET NULL,
    category        VARCHAR(30) NOT NULL,
    decision        VARCHAR(30) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_moderation_events_user ON moderation_events(user_id, created_at DESC);
CREATE INDEX idx_moderation_events_created_at ON moderation_events(created_at);

-- One row per user; escalates as violations accumulate. restricted_until
-- being in the future is what actually blocks sending (checked
-- server-side on every SendMessage) -- violation_count alone is just the
-- counter that drives escalation thresholds (see chatguard.AbuseConfig).
CREATE TABLE chat_restrictions (
    user_id           UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    violation_count   INT NOT NULL DEFAULT 0,
    restricted_until  TIMESTAMPTZ,
    flagged_for_review BOOLEAN NOT NULL DEFAULT false,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
