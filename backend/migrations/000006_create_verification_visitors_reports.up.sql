CREATE TABLE verifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    document_type   VARCHAR(30) NOT NULL, -- aadhaar, passport, driving_license, voter_id, pan
    document_key    VARCHAR(500) NOT NULL,
    document_url    VARCHAR(1000) NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending, approved, rejected
    reviewed_by     UUID REFERENCES users(id),
    review_notes    TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at     TIMESTAMPTZ
);

CREATE INDEX idx_verifications_user ON verifications(user_id, created_at DESC);
CREATE INDEX idx_verifications_status ON verifications(status);

CREATE TABLE profile_visits (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    visitor_user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    visited_user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    visit_date       DATE NOT NULL DEFAULT CURRENT_DATE,
    visited_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT profile_visits_no_self CHECK (visitor_user_id != visited_user_id)
);

-- One row per visitor/visited pair per day; repeat views the same day just
-- bump visited_at instead of growing the table unbounded.
CREATE UNIQUE INDEX idx_profile_visits_daily ON profile_visits (visitor_user_id, visited_user_id, visit_date);
CREATE INDEX idx_profile_visits_visited ON profile_visits(visited_user_id, visited_at DESC);

CREATE TABLE reports (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reported_user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason              VARCHAR(50) NOT NULL, -- fake_profile, inappropriate_content, harassment, spam, other
    details             TEXT,
    status              VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending, reviewed, dismissed, action_taken
    reviewed_by         UUID REFERENCES users(id),
    review_notes        TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at         TIMESTAMPTZ,

    CONSTRAINT reports_no_self CHECK (reporter_user_id != reported_user_id)
);

CREATE INDEX idx_reports_status ON reports(status);
CREATE INDEX idx_reports_reported_user ON reports(reported_user_id);
