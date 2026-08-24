DROP INDEX IF EXISTS idx_reports_priority_created;
ALTER TABLE reports DROP COLUMN IF EXISTS priority;
ALTER TABLE reports DROP COLUMN IF EXISTS category;
