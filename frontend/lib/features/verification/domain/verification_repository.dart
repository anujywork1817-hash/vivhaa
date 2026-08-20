import '../../../core/api/api_result.dart';

enum VerificationStatus { pending, approved, rejected }

class VerificationRecord {
  final String id;
  final VerificationStatus status;

  const VerificationRecord({required this.id, required this.status});
}

abstract class VerificationRepository {
  /// Uploads the captured selfie as an identity document for admin
  /// review. Returns the resulting (pending) record.
  Future<ApiResult<VerificationRecord>> submitSelfie(String filePath);

  /// The caller's most recent verification submission, or null if none
  /// has been submitted yet.
  Future<ApiResult<VerificationRecord?>> getStatus();
}
