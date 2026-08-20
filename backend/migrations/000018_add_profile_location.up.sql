-- GPS coordinates for the "Near Me" feature. Both null until the client
-- explicitly shares a location (never inferred from city/IP), so someone
-- who's never opened that feature simply doesn't show up in it.
ALTER TABLE profiles ADD COLUMN latitude DOUBLE PRECISION;
ALTER TABLE profiles ADD COLUMN longitude DOUBLE PRECISION;
ALTER TABLE profiles ADD COLUMN location_updated_at TIMESTAMPTZ;

ALTER TABLE profiles ADD CONSTRAINT profiles_latitude_range
    CHECK (latitude IS NULL OR (latitude BETWEEN -90 AND 90));
ALTER TABLE profiles ADD CONSTRAINT profiles_longitude_range
    CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180));

-- The nearby query filters to "has shared a location" before doing any
-- distance math, so this is the index that matters for it.
CREATE INDEX idx_profiles_has_location ON profiles (latitude, longitude)
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
