enum MessageKind { text, contactRequest, contactAccepted, contactDeclined, contactShared, system }

class ChatMessage {
  final String id;
  final String text;
  final bool fromMe;
  final DateTime timestamp;
  final MessageKind kind;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.fromMe,
    required this.timestamp,
    this.kind = MessageKind.text,
  });
}
