ALTER TABLE preferences
    ADD COLUMN profession          VARCHAR(150),
    ADD COLUMN working_with        VARCHAR(50),
    ADD COLUMN profile_managed_by  VARCHAR(30);

CREATE TABLE saved_searches (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name          VARCHAR(100) NOT NULL,
    filters       JSONB NOT NULL,
    result_count  INT NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_saved_searches_user ON saved_searches(user_id);
