-- Image/camera/document attachments in chat: a new column for the
-- uploaded file's public URL, and two new kind values. attachment_url is
-- nullable and only ever set for kind IN ('image','document') — a plain
-- text/contact-* message never has one.
ALTER TABLE chat_messages ADD COLUMN attachment_url VARCHAR(1000);

ALTER TABLE chat_messages DROP CONSTRAINT chat_messages_kind_check;
ALTER TABLE chat_messages ADD CONSTRAINT chat_messages_kind_check
    CHECK (kind IN ('text', 'contact_request', 'contact_accepted', 'contact_declined', 'contact_shared', 'image', 'document'));
