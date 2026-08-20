import '../../../core/api/api_result.dart';

enum VerificationStatus { pending, approved, rejected }

class VerificationRecord {
  final String id;
  final String documentType;
  final VerificationStatus status;

  const VerificationRecord({
    required this.id,
    required this.documentType,
    required this.status,
  });
}

abstract class VerificationRepository {
  /// Uploads the captured selfie as an identity document for admin
  /// review. Returns the resulting (pending) record.
  Future<ApiResult<VerificationRecord>> submitSelfie(String filePath);

  /// The caller's most recent verification submission, or null if none
  /// has been submitted yet.
  Future<ApiResult<VerificationRecord?>> getStatus();

  /// Uploads an arbitrary supporting document (photo or PDF) for admin
  /// review — e.g. `documentType: 'personal_document'`. Like
  /// [submitSelfie], this always lands in "pending"; it is never an
  /// instant pass/fail.
  Future<ApiResult<VerificationRecord>> submitDocument({
    required String documentType,
    required List<int> bytes,
    required String filename,
    required String contentType,
  });

  /// Every verification document the caller has ever submitted, newest
  /// first.
  Future<ApiResult<List<VerificationRecord>>> listMine();
}
