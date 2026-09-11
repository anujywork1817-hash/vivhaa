-- The original soft-delete (000016) used one shared deleted_at column,
-- so deleting an interest from either side hid it from BOTH parties'
-- inbox lists — a request the current user never touched could
-- disappear (and show up under Deleted) purely because the other party
-- deleted their own copy. "Delete" (removing something from your own
-- Inbox/Sent list) should be a personal action, not a mutual one.
--
-- Accept/Decline/chat-access-revocation ("unmatch") intentionally stay
-- symmetric (see IsAccepted/GetByID's BUG-H09 comments) - those check
-- "deleted by either side," unchanged by this migration. Only the list
-- views (ListSent/ListReceived/ListDeleted) become per-party.
ALTER TABLE interests ADD COLUMN sender_deleted_at TIMESTAMPTZ;
ALTER TABLE interests ADD COLUMN receiver_deleted_at TIMESTAMPTZ;

-- Historical deletions can't be attributed to a side after the fact, so
-- both are backfilled to preserve exactly the current (hidden-from-both)
-- state for existing rows — this only changes behavior for deletions
-- from this point forward.
UPDATE interests SET sender_deleted_at = deleted_at, receiver_deleted_at = deleted_at
WHERE deleted_at IS NOT NULL;

DROP INDEX IF EXISTS interests_unique_active_pair;
DROP INDEX IF EXISTS idx_interests_deleted;

-- Same "one active interest per pair" rule as before: a pair frees up
-- for a new request as soon as either side's copy is gone, matching the
-- original index's behavior exactly.
CREATE UNIQUE INDEX interests_unique_active_pair
    ON interests (sender_user_id, receiver_user_id)
    WHERE sender_deleted_at IS NULL AND receiver_deleted_at IS NULL;

CREATE INDEX idx_interests_sender_deleted ON interests (sender_deleted_at)
    WHERE sender_deleted_at IS NOT NULL;
CREATE INDEX idx_interests_receiver_deleted ON interests (receiver_deleted_at)
    WHERE receiver_deleted_at IS NOT NULL;

ALTER TABLE interests DROP COLUMN deleted_at;
