-- Distinguishes plain text messages from contact-request lifecycle
-- messages, so the contact-number reveal flow can require the target's
-- explicit accept/decline instead of resolving instantly. The request
-- message's own row is what gets mutated on accept/decline (pending ->
-- accepted/declined), so there's no need for a separate requests table.
ALTER TABLE chat_messages ADD COLUMN kind VARCHAR(20) NOT NULL DEFAULT 'text';

ALTER TABLE chat_messages ADD CONSTRAINT chat_messages_kind_check
    CHECK (kind IN ('text', 'contact_request', 'contact_accepted', 'contact_declined', 'contact_shared'));

-- Speeds up the "is there already a pending request from A to B" check
-- RequestContact runs before creating a new one.
CREATE INDEX idx_chat_messages_pending_contact
    ON chat_messages (sender_user_id, receiver_user_id)
    WHERE kind = 'contact_request';
