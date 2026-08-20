-- Push notification registration tokens, one row per device a user is
-- signed in on. Push delivery is addressed per-device, but the rest of the
-- system only knows about users, so this is the lookup that turns a
-- user-targeted notification into the set of devices to actually send to.
CREATE TABLE device_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token       TEXT NOT NULL,
    platform    VARCHAR(16) NOT NULL DEFAULT 'android', -- android | ios | web
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- FCM reissues the same token to whoever installs next, so a token can
    -- legitimately move between users (shared/resold device, or a sign-out
    -- and sign-in as someone else). Uniqueness is on the token alone so
    -- re-registering reassigns it rather than delivering one user's
    -- notifications to another's device.
    CONSTRAINT device_tokens_token_unique UNIQUE (token)
);

CREATE INDEX idx_device_tokens_user ON device_tokens(user_id);
