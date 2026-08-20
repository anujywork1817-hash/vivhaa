DROP INDEX IF EXISTS idx_chat_messages_pending_contact;
ALTER TABLE chat_messages DROP CONSTRAINT IF EXISTS chat_messages_kind_check;
ALTER TABLE chat_messages DROP COLUMN IF EXISTS kind;
