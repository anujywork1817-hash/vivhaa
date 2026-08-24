import '../../../core/api/api_result.dart';
import '../../../shared/models/profile_detail.dart';
import '../../../shared/models/match_profile.dart';

/// Phone/email revealed by `GET /profiles/:id/contact`. The backend gates
/// this behind the premium "view_contact" feature, so a non-premium caller
/// gets a failure rather than an empty result.
class ContactInfo {
  final String? phone;
  final String? email;
  const ContactInfo({this.phone, this.email});
}

abstract class ProfileDetailRepository {
  Future<ApiResult<ProfileDetail>> getProfileDetail(String id);
  Future<ApiResult<List<MatchProfile>>> getSimilarProfiles(String id, {int count = 6});
  Future<ApiResult<void>> reportProfile(String id, String reason, {String? details});
  Future<ApiResult<ContactInfo>> getContact(String id);
}
