-- Soft-delete for interests, so a removed request can still be listed
-- under Inbox > More > Deleted instead of vanishing without trace.
ALTER TABLE interests ADD COLUMN deleted_at TIMESTAMPTZ;

-- The old unique pair constraint counted deleted rows, which would
-- permanently bar you from ever contacting someone again once a request
-- to them was deleted. A partial index scoped to live rows keeps the
-- "one active interest per pair" rule while allowing a fresh request
-- after a deletion.
ALTER TABLE interests DROP CONSTRAINT interests_unique_pair;

CREATE UNIQUE INDEX interests_unique_active_pair
    ON interests (sender_user_id, receiver_user_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_interests_deleted ON interests (deleted_at)
    WHERE deleted_at IS NOT NULL;
