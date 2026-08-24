enum MessageKind { text, contactRequest, contactAccepted, contactDeclined, contactShared, image, document, system }

/// Truncated (140 char) snapshot of a message being replied to, for
/// rendering a quoted preview inside the replying message's bubble. Mirrors
/// the backend's `reply_to` object on `MessageResponse`.
class ReplyToPreview {
  final String id;
  final String body;
  final String senderUserId;

  const ReplyToPreview({
    required this.id,
    required this.body,
    required this.senderUserId,
  });

  factory ReplyToPreview.fromJson(Map<String, dynamic> json) {
    return ReplyToPreview(
      id: json['id'] as String,
      body: json['body'] as String,
      senderUserId: json['sender_user_id'] as String,
    );
  }
}

class ChatMessage {
  final String id;
  final String text;
  final bool fromMe;
  final DateTime timestamp;
  final MessageKind kind;
  final ReplyToPreview? replyTo;
  final String? attachmentUrl;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.fromMe,
    required this.timestamp,
    this.kind = MessageKind.text,
    this.replyTo,
    this.attachmentUrl,
  });
}
