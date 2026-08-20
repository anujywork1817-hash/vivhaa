import 'match_profile.dart';

enum InterestStatus { pending, accepted, declined }

enum InterestDirection { sent, received }

class InterestRecord {
  final String id;
  final MatchProfile profile;
  final InterestDirection direction;
  final InterestStatus status;
  final DateTime timestamp;

  /// The other party's gender, used only to pick pronouns in copy
  /// ("Accepted by her" / "Viewed by him"). Null when unknown, in which
  /// case callers fall back to gender-neutral wording.
  final String? otherGender;

  /// When the recipient first saw this request; null means not yet seen.
  /// Only meaningful on interests you sent.
  final DateTime? viewedAt;

  const InterestRecord({
    required this.id,
    required this.profile,
    required this.direction,
    required this.status,
    required this.timestamp,
    this.otherGender,
    this.viewedAt,
  });

  bool get isViewed => viewedAt != null;

  /// "her" / "him" / "them" — the last covers a profile with no gender set,
  /// rather than guessing.
  String get objectPronoun => switch (otherGender) {
        'female' => 'her',
        'male' => 'him',
        _ => 'them',
      };

  InterestRecord copyWith({InterestStatus? status}) {
    return InterestRecord(
      id: id,
      profile: profile,
      direction: direction,
      status: status ?? this.status,
      timestamp: timestamp,
      otherGender: otherGender,
      viewedAt: viewedAt,
    );
  }
}
