-- When the recipient first saw an interest. Drives the sender-side
-- "Viewed / Not viewed yet" filter: without it there's no way to tell a
-- request that's been ignored from one that simply hasn't been seen.
-- NULL means not yet viewed.
ALTER TABLE interests ADD COLUMN viewed_at TIMESTAMPTZ;

-- Partial index: the "not viewed yet" filter only ever scans NULLs, and
-- most rows become non-NULL over time.
CREATE INDEX idx_interests_receiver_unviewed
    ON interests (receiver_user_id)
    WHERE viewed_at IS NULL;
