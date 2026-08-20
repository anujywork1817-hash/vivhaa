CREATE TABLE profiles (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

    full_name            VARCHAR(150),
    date_of_birth        DATE,
    gender               VARCHAR(20),   -- male, female, other
    height_cm            SMALLINT,
    marital_status       VARCHAR(30),   -- never_married, divorced, widowed, awaiting_divorce

    religion             VARCHAR(50),
    community            VARCHAR(100),  -- caste / community
    mother_tongue        VARCHAR(50),

    education            VARCHAR(150),
    occupation           VARCHAR(150),
    annual_income_inr    BIGINT,

    country              VARCHAR(100),
    state                VARCHAR(100),
    city                 VARCHAR(100),

    family_type          VARCHAR(30),   -- nuclear, joint
    family_status        VARCHAR(30),   -- middle_class, upper_middle_class, affluent, rich
    father_occupation     VARCHAR(150),
    mother_occupation     VARCHAR(150),
    siblings_count        SMALLINT,

    diet                 VARCHAR(30),   -- vegetarian, non_vegetarian, eggetarian, vegan
    smoking               VARCHAR(20),   -- no, occasionally, yes
    drinking               VARCHAR(20),  -- no, occasionally, yes
    about_me              TEXT,

    visibility            VARCHAR(20) NOT NULL DEFAULT 'public', -- public, private

    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_profiles_user_id ON profiles(user_id);
CREATE INDEX idx_profiles_religion ON profiles(religion);
CREATE INDEX idx_profiles_city ON profiles(city);

CREATE TABLE profile_photos (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    object_key  VARCHAR(500) NOT NULL,
    url         VARCHAR(1000) NOT NULL,
    is_primary  BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order  SMALLINT NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_profile_photos_profile_id ON profile_photos(profile_id);
