DROP INDEX IF EXISTS idx_chat_messages_sender_deleted;
DROP INDEX IF EXISTS idx_chat_messages_receiver_deleted;
ALTER TABLE chat_messages DROP COLUMN sender_deleted_at;
ALTER TABLE chat_messages DROP COLUMN receiver_deleted_at;
ALTER TABLE chat_messages DROP COLUMN deleted_for_everyone_at;
