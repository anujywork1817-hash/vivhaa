DROP INDEX IF EXISTS idx_interests_receiver_unviewed;
ALTER TABLE interests DROP COLUMN IF EXISTS viewed_at;
