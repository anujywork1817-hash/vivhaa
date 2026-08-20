DROP INDEX IF EXISTS idx_profiles_has_location;
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_longitude_range;
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_latitude_range;
ALTER TABLE profiles DROP COLUMN IF EXISTS location_updated_at;
ALTER TABLE profiles DROP COLUMN IF EXISTS longitude;
ALTER TABLE profiles DROP COLUMN IF EXISTS latitude;
