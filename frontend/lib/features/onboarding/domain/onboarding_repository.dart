import '../../../core/api/api_result.dart';
import '../../../shared/models/profile.dart';

/// Outcome of a profile submit. Photo uploads are a separate step that can
/// fail on their own (size/format rejection, flaky upload) while the
/// profile fields themselves saved fine, so the two outcomes are reported
/// independently rather than collapsing into one success/failure.
class ProfileSubmitResult {
  final Profile profile;
  final int photoUploadFailures;

  const ProfileSubmitResult({required this.profile, this.photoUploadFailures = 0});
}

abstract class OnboardingRepository {
  Future<ApiResult<ProfileSubmitResult>> submitProfile(Profile profile);

  /// Returns the caller's existing profile, or `null` (as a success) if
  /// they haven't created one yet — distinct from an [ApiFailure], which
  /// means the lookup itself failed.
  Future<ApiResult<Profile?>> getMyProfile();
}
