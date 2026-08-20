import 'match_profile.dart';

/// One entry in "who viewed my profile" — pairs a visitor's profile with
/// when they visited.
class VisitorRecord {
  final MatchProfile profile;
  final DateTime visitedAt;

  const VisitorRecord({required this.profile, required this.visitedAt});
}
