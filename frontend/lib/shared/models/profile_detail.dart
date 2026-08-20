import 'match_profile.dart';

/// Everything shown on the full profile-detail screen — wraps the
/// lightweight [MatchProfile] card data with the richer fields only
/// needed once someone opens a profile.
class ProfileDetail {
  final MatchProfile summary;
  final List<String> photoIds;
  final String about;
  final String fatherOccupation;
  final String motherOccupation;
  final int brothers;
  final int sisters;
  final String familyType;
  final String familyValues;
  final String smoking;
  final String drinking;
  final String rashi;
  final String nakshatra;
  final String partnerPreferenceSummary;
  final bool idVerified;
  final bool phoneVerified;
  final bool photoVerified;

  const ProfileDetail({
    required this.summary,
    required this.photoIds,
    required this.about,
    required this.fatherOccupation,
    required this.motherOccupation,
    required this.brothers,
    required this.sisters,
    required this.familyType,
    required this.familyValues,
    required this.smoking,
    required this.drinking,
    required this.rashi,
    required this.nakshatra,
    required this.partnerPreferenceSummary,
    required this.idVerified,
    required this.phoneVerified,
    required this.photoVerified,
  });
}
