-- WhatsApp-style message deletion: "delete for me" hides a message from
-- only the requester's own view (same per-party pattern 000033 used for
-- interests — each side gets its own column rather than one shared flag,
-- so deleting your own copy can never make it vanish for the other
-- person too). "Delete for everyone" is a separate, symmetric flag: only
-- the original sender can set it, and once set the message is gone for
-- both sides regardless of their own per-party columns.
ALTER TABLE chat_messages ADD COLUMN sender_deleted_at TIMESTAMPTZ;
ALTER TABLE chat_messages ADD COLUMN receiver_deleted_at TIMESTAMPTZ;
ALTER TABLE chat_messages ADD COLUMN deleted_for_everyone_at TIMESTAMPTZ;

CREATE INDEX idx_chat_messages_sender_deleted ON chat_messages (sender_deleted_at)
    WHERE sender_deleted_at IS NOT NULL;
CREATE INDEX idx_chat_messages_receiver_deleted ON chat_messages (receiver_deleted_at)
    WHERE receiver_deleted_at IS NOT NULL;
