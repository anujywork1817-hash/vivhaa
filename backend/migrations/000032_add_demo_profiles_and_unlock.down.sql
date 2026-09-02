DROP TABLE IF EXISTS unlock_payments;
ALTER TABLE users DROP COLUMN IF EXISTS unlocked_at;
DROP INDEX IF EXISTS idx_profiles_is_demo;
ALTER TABLE profiles DROP COLUMN IF EXISTS is_demo;
