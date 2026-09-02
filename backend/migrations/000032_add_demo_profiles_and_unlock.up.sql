-- "Hook then pay ₹1" onboarding gate.
--
-- is_demo marks the fixed pool of 10 male + 10 female demo profiles shown
-- to every new user in the free swipe-deck hook (see internal/demo). They
-- must never be counted as real matches, must never be recommended/
-- searched against each other or against real users, and only ever appear
-- via the dedicated demo swipe-deck endpoint.
ALTER TABLE profiles ADD COLUMN is_demo BOOLEAN NOT NULL DEFAULT false;

-- Used by the demo swipe-deck query (pull the fixed pool by gender) and by
-- matchmaking/search exclusion filters.
CREATE INDEX idx_profiles_is_demo ON profiles (is_demo) WHERE is_demo;

-- unlocked_at is set once, permanently, the first time a user completes
-- the ₹1 unlock payment (internal/unlock). NULL means still gated. This is
-- deliberately separate from the subscription/premium tier system in
-- internal/subscriptions — the unlock is a one-time front gate, not a plan.
ALTER TABLE users ADD COLUMN unlocked_at TIMESTAMPTZ NULL;

-- Minimal, separate payment-tracking table for the ₹1 unlock flow — kept
-- apart from the plan-based `payments` table (internal/payments) since
-- that table's schema assumes a plan_id/subscription_id, neither of which
-- applies here.
CREATE TABLE unlock_payments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    amount_inr          BIGINT NOT NULL,
    currency            VARCHAR(10) NOT NULL DEFAULT 'INR',
    razorpay_order_id   VARCHAR(100) NOT NULL UNIQUE,
    razorpay_payment_id VARCHAR(100),
    razorpay_signature  VARCHAR(255),
    status              VARCHAR(20) NOT NULL DEFAULT 'created', -- created, paid, failed
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    paid_at             TIMESTAMPTZ
);

CREATE INDEX idx_unlock_payments_user_id ON unlock_payments (user_id);
