-- Replaces the Monthly/Quarterly plan picker with a single one-time
-- payment for lifetime access — same "very long duration_days stands in
-- for forever" convention the 'free' plan already established (see
-- 000007), so no new "never expires" concept is needed anywhere else in
-- the codebase (subscription expiry checks, the admin dashboard, etc.
-- all already just compare against ends_at).
INSERT INTO subscription_plans (code, name, price_inr, duration_days, features, tier_rank) VALUES
    ('premium_lifetime', 'Premium Lifetime', 2, 36500, '{"chat": true, "view_contact": true, "unlimited_interests": true}', 1);

-- Deactivated, not deleted — existing subscriptions/payments still
-- reference these rows via plan_id, and is_active is exactly the flag
-- the plans-list endpoint already filters on.
UPDATE subscription_plans SET is_active = FALSE WHERE code IN ('premium_monthly', 'premium_quarterly', 'premium_yearly');
