CREATE TABLE preferences (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

    min_age          SMALLINT,
    max_age          SMALLINT,
    min_height_cm    SMALLINT,
    max_height_cm    SMALLINT,

    marital_status   TEXT[],
    religion         TEXT[],
    community        TEXT[],
    mother_tongue    TEXT[],
    education        TEXT[],
    min_income_inr   BIGINT,
    country          TEXT[],
    state            TEXT[],
    city             TEXT[],
    diet             TEXT[],

    about_partner    TEXT,

    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE interests (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status           VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending, accepted, declined
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at     TIMESTAMPTZ,

    CONSTRAINT interests_no_self CHECK (sender_user_id != receiver_user_id),
    CONSTRAINT interests_unique_pair UNIQUE (sender_user_id, receiver_user_id)
);

CREATE INDEX idx_interests_sender ON interests(sender_user_id);
CREATE INDEX idx_interests_receiver ON interests(receiver_user_id);

CREATE TABLE favourites (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT favourites_no_self CHECK (user_id != target_user_id),
    CONSTRAINT favourites_unique_pair UNIQUE (user_id, target_user_id)
);

CREATE INDEX idx_favourites_user ON favourites(user_id);

CREATE TABLE shortlisted_profiles (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT shortlisted_no_self CHECK (user_id != target_user_id),
    CONSTRAINT shortlisted_unique_pair UNIQUE (user_id, target_user_id)
);

CREATE INDEX idx_shortlisted_user ON shortlisted_profiles(user_id);
