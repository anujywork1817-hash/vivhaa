import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:image_picker/image_picker.dart' show XFile;
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../domain/verification_repository.dart';

/// Talks to the real matrimony_backend `/verification/*` endpoints. The
/// backend's document-verification flow is admin-reviewed and
/// async — submitting here always lands in "pending", not an instant
/// pass/fail, regardless of what the surrounding screens' copy implies.
class ApiVerificationRepository implements VerificationRepository {
  final ApiClient _client;

  ApiVerificationRepository(this._client);

  @override
  Future<ApiResult<VerificationRecord>> submitSelfie(String filePath) async {
    try {
      final xfile = XFile(filePath);
      final bytes = await xfile.readAsBytes();
      final filename = xfile.name.isNotEmpty ? xfile.name : 'selfie.jpg';
      final response = await _client.dio.post(
        ApiEndpoints.verificationSubmit,
        data: FormData.fromMap({
          'document_type': 'selfie',
          'document': MultipartFile.fromBytes(bytes, filename: filename),
        }),
      );
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(_fromJson(data));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<VerificationRecord?>> getStatus() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.verificationStatus);
      return ApiResult.success(_fromJson(response.data['data'] as Map<String, dynamic>));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const ApiResult.success(null);
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<VerificationRecord>> submitDocument({
    required String documentType,
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.verificationSubmit,
        data: FormData.fromMap({
          'document_type': documentType,
          'document': MultipartFile.fromBytes(
            bytes,
            filename: filename,
            contentType: MediaType.parse(contentType),
          ),
        }),
      );
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(_fromJson(data));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<VerificationRecord>>> listMine() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.verificationMine);
      final data = response.data['data'] as List<dynamic>;
      return ApiResult.success(
        data.map((e) => _fromJson(e as Map<String, dynamic>)).toList(),
      );
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  VerificationRecord _fromJson(Map<String, dynamic> json) {
    return VerificationRecord(
      id: json['id'] as String,
      documentType: json['document_type'] as String? ?? '',
      status: _statusFromBackend(json['status'] as String),
    );
  }

  VerificationStatus _statusFromBackend(String status) {
    switch (status) {
      case 'approved':
        return VerificationStatus.approved;
      case 'rejected':
        return VerificationStatus.rejected;
      default:
        return VerificationStatus.pending;
    }
  }
}

final verificationRepositoryProvider = Provider<VerificationRepository>((ref) {
  return ApiVerificationRepository(ref.watch(apiClientProvider));
});
