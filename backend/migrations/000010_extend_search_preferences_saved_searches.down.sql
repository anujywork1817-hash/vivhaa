DROP TABLE IF EXISTS saved_searches;

ALTER TABLE preferences
    DROP COLUMN IF EXISTS profession,
    DROP COLUMN IF EXISTS working_with,
    DROP COLUMN IF EXISTS profile_managed_by;
