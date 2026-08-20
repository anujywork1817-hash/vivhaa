enum AiMessageRole { user, assistant }

class AiMessage {
  final String id;
  final AiMessageRole role;
  final String content;
  final DateTime timestamp;

  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
  });
}
