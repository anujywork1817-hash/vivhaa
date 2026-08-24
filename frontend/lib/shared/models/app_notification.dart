enum NotificationType { interest, visitor, match, message, system }

class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool read;

  /// The backend's raw `data` payload (e.g. `{"interest_id": ...}` for an
  /// interest notification, `{"sender_user_id": ..., "message_id": ...}`
  /// for a chat one) — carried through so tapping a notification can
  /// navigate to the specific thing it's about, not just mark it read.
  final Map<String, dynamic> data;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.read = false,
    this.data = const {},
  });

  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      timestamp: timestamp,
      read: read ?? this.read,
      data: data,
    );
  }
}
