ALTER TABLE chat_messages DROP CONSTRAINT chat_messages_kind_check;
ALTER TABLE chat_messages ADD CONSTRAINT chat_messages_kind_check
    CHECK (kind IN ('text', 'contact_request', 'contact_accepted', 'contact_declined', 'contact_shared'));

ALTER TABLE chat_messages DROP COLUMN IF EXISTS attachment_url;
