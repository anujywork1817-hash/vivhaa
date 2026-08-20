import 'match_profile.dart';

class Conversation {
  final String id;
  final MatchProfile withProfile;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;
  final bool contactShared;
  // True when either side has blocked the other. The thread still shows
  // up (message history isn't deleted on block) but messaging is
  // disabled and the list marks it as blocked rather than looking like
  // an ordinary, functional conversation.
  final bool isBlocked;

  const Conversation({
    required this.id,
    required this.withProfile,
    required this.lastMessage,
    required this.lastMessageAt,
    this.unreadCount = 0,
    this.contactShared = false,
    this.isBlocked = false,
  });

  Conversation copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
    bool? contactShared,
    bool? isBlocked,
  }) {
    return Conversation(
      id: id,
      withProfile: withProfile,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      contactShared: contactShared ?? this.contactShared,
      isBlocked: isBlocked ?? this.isBlocked,
    );
  }
}
