CREATE TABLE subscription_plans (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code           VARCHAR(30) NOT NULL UNIQUE,
    name           VARCHAR(100) NOT NULL,
    price_inr      BIGINT NOT NULL,
    duration_days  INT NOT NULL,
    features       JSONB NOT NULL DEFAULT '{}',
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- price_inr is whole rupees (e.g. 999 = Rs 999); converted to paise only
-- at the payment-gateway boundary, where Razorpay's API requires it.
INSERT INTO subscription_plans (code, name, price_inr, duration_days, features) VALUES
    ('free',              'Free',              0,    36500, '{}'),
    ('premium_monthly',   'Premium Monthly',   999,  30,    '{"chat": true, "view_contact": true, "unlimited_interests": true}'),
    ('premium_quarterly', 'Premium Quarterly', 2499, 90,    '{"chat": true, "view_contact": true, "unlimited_interests": true}');

CREATE TABLE subscriptions (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_id      UUID NOT NULL REFERENCES subscription_plans(id),
    status       VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending, active, expired, cancelled
    starts_at    TIMESTAMPTZ,
    ends_at      TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_subscriptions_user ON subscriptions(user_id, created_at DESC);
CREATE INDEX idx_subscriptions_active ON subscriptions(user_id, status) WHERE status = 'active';

CREATE TABLE coupons (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code            VARCHAR(50) NOT NULL UNIQUE,
    description     VARCHAR(255),
    discount_type   VARCHAR(10) NOT NULL, -- percent, flat
    discount_value  BIGINT NOT NULL,
    max_uses        INT,
    used_count      INT NOT NULL DEFAULT 0,
    valid_from      TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until     TIMESTAMPTZ,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO coupons (code, description, discount_type, discount_value, max_uses, valid_until) VALUES
    ('WELCOME10', '10% off your first subscription', 'percent', 10, 1000, now() + interval '1 year');

CREATE TABLE payments (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_id              UUID NOT NULL REFERENCES subscription_plans(id),
    subscription_id      UUID REFERENCES subscriptions(id),
    coupon_id            UUID REFERENCES coupons(id),
    amount_inr           BIGINT NOT NULL,
    discount_inr         BIGINT NOT NULL DEFAULT 0,
    currency             VARCHAR(3) NOT NULL DEFAULT 'INR',
    razorpay_order_id    VARCHAR(100) NOT NULL UNIQUE,
    razorpay_payment_id  VARCHAR(100),
    razorpay_signature   VARCHAR(255),
    status               VARCHAR(20) NOT NULL DEFAULT 'created', -- created, paid, failed, refunded
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    paid_at              TIMESTAMPTZ
);

CREATE INDEX idx_payments_user ON payments(user_id, created_at DESC);
CREATE INDEX idx_payments_order_id ON payments(razorpay_order_id);
