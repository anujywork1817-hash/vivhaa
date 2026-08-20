-- Reverts document_url to NOT NULL. Only safe to run if every row still
-- has a non-null document_url — will fail otherwise.
ALTER TABLE verifications ALTER COLUMN document_url SET NOT NULL;
