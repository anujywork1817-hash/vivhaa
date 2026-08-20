DROP INDEX IF EXISTS idx_interests_deleted;
DROP INDEX IF EXISTS interests_unique_active_pair;

-- Deleted rows must go before the unconditional constraint can be restored,
-- otherwise a soft-deleted duplicate pair would violate it.
DELETE FROM interests WHERE deleted_at IS NOT NULL;

ALTER TABLE interests ADD CONSTRAINT interests_unique_pair UNIQUE (sender_user_id, receiver_user_id);
ALTER TABLE interests DROP COLUMN IF EXISTS deleted_at;
