-- Ordered tier ranking so "is this plan an upgrade from the caller's
-- current plan" can be computed generically (target.tier_rank >
-- current.tier_rank) instead of scattering per-plan-code if-statements
-- across the codebase. Free is rank 0; each paid duration ranks above
-- the last (Monthly < Quarterly < Yearly). Adding a future tier is just
-- another row with the next rank — no code change needed to place it in
-- the hierarchy.
ALTER TABLE subscription_plans ADD COLUMN tier_rank INT NOT NULL DEFAULT 0;

UPDATE subscription_plans SET tier_rank = 0 WHERE code = 'free';
UPDATE subscription_plans SET tier_rank = 1 WHERE code = 'premium_monthly';
UPDATE subscription_plans SET tier_rank = 2 WHERE code = 'premium_quarterly';
UPDATE subscription_plans SET tier_rank = 3 WHERE code = 'premium_yearly';
