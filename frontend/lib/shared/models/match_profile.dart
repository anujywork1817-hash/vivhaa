/// A lightweight profile card shown in match lists — the dashboard,
/// search results, shortlist, etc. Distinct from the full [Profile] model
/// used during profile creation; this is what one member sees of another.
class MatchProfile {
  final String id;
  final String name;
  final int age;
  final int heightCm;
  final String city;
  final String? state;
  final String? motherTongue;
  final String profession;
  final String education;
  final String religion;
  final String maritalStatus;
  final String diet;
  final String manglik;
  final String incomeBracket;
  final String? community;
  final bool verified;
  final bool isNew;
  final double matchScore;
  final String? photoSeed;

  /// The backend's real, persisted profile code (e.g. "VV100042"), when
  /// known. Falls back to a deterministic hash of [id] when the source
  /// endpoint didn't provide one, so every card still has *some* code to
  /// display.
  final String? backendProfileCode;

  /// True when this member has restricted their photo to members
  /// they're connected to — shown blurred/frosted until an interest
  /// between the two profiles is accepted.
  final bool photoLocked;

  /// Distance from the viewer in kilometres — only populated by the
  /// "Near Me" endpoint, null everywhere else.
  final double? distanceKm;

  const MatchProfile({
    required this.id,
    required this.name,
    required this.age,
    required this.heightCm,
    required this.city,
    this.state,
    this.motherTongue,
    required this.profession,
    required this.education,
    required this.religion,
    this.maritalStatus = 'Never Married',
    this.diet = 'Vegetarian',
    this.manglik = "Don't know",
    this.incomeBracket = '₹6–10 Lakh',
    this.community,
    this.verified = false,
    this.isNew = false,
    this.matchScore = 0,
    this.photoSeed,
    this.backendProfileCode,
    this.photoLocked = false,
    this.distanceKm,
  });

  String get heightLabel {
    final feet = (heightCm / 30.48).floor();
    final inches = ((heightCm / 2.54) % 12).round();
    return "$feet' $inches\"";
  }

  /// The backend's real profile code when available; otherwise a
  /// deterministic fallback derived from [id] so there's always something
  /// to display.
  String get profileCode {
    if (backendProfileCode != null && backendProfileCode!.isNotEmpty) {
      return backendProfileCode!;
    }
    final numeric = id.codeUnits.fold<int>(0, (a, b) => a * 31 + b) % 900000 + 100000;
    return 'VV$numeric';
  }
}
