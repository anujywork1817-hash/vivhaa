UPDATE subscription_plans SET is_active = TRUE WHERE code IN ('premium_monthly', 'premium_quarterly', 'premium_yearly');
DELETE FROM subscription_plans WHERE code = 'premium_lifetime';
