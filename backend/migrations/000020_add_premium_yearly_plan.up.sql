-- A third paid duration alongside premium_monthly/premium_quarterly, for
-- the frontend's Platinum (monthly) / Silver (quarterly) / Gold (yearly)
-- tier picker. Priced for a meaningfully better per-month rate than
-- quarterly (~₹667/mo vs quarterly's ~₹833/mo), same feature set as the
-- other paid plans.
INSERT INTO subscription_plans (code, name, price_inr, duration_days, features) VALUES
    ('premium_yearly', 'Premium Yearly', 7999, 365, '{"chat": true, "view_contact": true, "unlimited_interests": true}');
