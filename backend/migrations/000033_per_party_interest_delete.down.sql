ALTER TABLE interests ADD COLUMN deleted_at TIMESTAMPTZ;

-- Reconstruct the shared column: a row deleted by either side becomes
-- deleted for both again, matching the pre-migration behavior.
UPDATE interests SET deleted_at = COALESCE(sender_deleted_at, receiver_deleted_at)
WHERE sender_deleted_at IS NOT NULL OR receiver_deleted_at IS NOT NULL;

DROP INDEX IF EXISTS idx_interests_sender_deleted;
DROP INDEX IF EXISTS idx_interests_receiver_deleted;
DROP INDEX IF EXISTS interests_unique_active_pair;

CREATE UNIQUE INDEX interests_unique_active_pair
    ON interests (sender_user_id, receiver_user_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_interests_deleted ON interests (deleted_at)
    WHERE deleted_at IS NOT NULL;

ALTER TABLE interests DROP COLUMN sender_deleted_at;
ALTER TABLE interests DROP COLUMN receiver_deleted_at;
