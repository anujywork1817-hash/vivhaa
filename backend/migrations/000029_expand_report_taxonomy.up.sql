-- Broadens reports from 5 generic reasons to a real taxonomy (profile /
-- chat / photo / safety / money categories), and lets a "safety" report
-- surface first in the admin queue instead of competing on created_at
-- alone with routine spam reports.
ALTER TABLE reports ADD COLUMN category VARCHAR(20) NOT NULL DEFAULT 'profile';
ALTER TABLE reports ADD COLUMN priority VARCHAR(10) NOT NULL DEFAULT 'normal';

CREATE INDEX idx_reports_priority_created ON reports(priority, created_at DESC) WHERE status = 'pending';
