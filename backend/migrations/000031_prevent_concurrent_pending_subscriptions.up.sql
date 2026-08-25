-- Prevents two concurrent Checkout() calls from the same user both
-- passing the "am I already checking out" check and creating two pending
-- subscriptions for two different plans — if both are then paid, the
-- user could be double-charged. A partial unique index makes this
-- impossible at the database level (atomic, unlike an application-level
-- check-then-insert), rather than merely unlikely.
CREATE UNIQUE INDEX idx_subscriptions_one_pending_per_user
    ON subscriptions(user_id) WHERE status = 'pending';
