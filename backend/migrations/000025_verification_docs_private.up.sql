-- BUG-C06: verification documents move to a private bucket, accessed only
-- via short-lived signed URLs generated on demand — never a permanently
-- stored public link. document_url is no longer written by the app; new
-- rows insert NULL. Existing rows keep their old (now-stale) public URL
-- for audit purposes only — it's never read by the API anymore.
ALTER TABLE verifications ALTER COLUMN document_url DROP NOT NULL;
