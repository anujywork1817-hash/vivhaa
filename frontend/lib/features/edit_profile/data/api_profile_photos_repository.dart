import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/models/profile_photo.dart';

/// Gallery management for the caller's own photos, against the real
/// `/profiles/me/photos*` endpoints. Separate from the onboarding
/// repository, which only ever uploads photos as part of submitting the
/// whole profile — this covers listing, deleting and choosing which one is
/// the profile picture.
class ApiProfilePhotosRepository {
  final ApiClient _client;

  ApiProfilePhotosRepository(this._client);

  /// The backend has no dedicated "list photos" route — photos come back
  /// embedded in the profile, which is also the only place their primary
  /// flag lives.
  Future<ApiResult<List<ProfilePhoto>>> list() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.myProfile);
      final data = response.data['data'] as Map<String, dynamic>;
      final rows = (data['photos'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(ProfilePhoto.fromJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  Future<ApiResult<ProfilePhoto>> upload(String path) async {
    try {
      final xfile = XFile(path);
      final bytes = await xfile.readAsBytes();
      final filename = xfile.name.isNotEmpty ? xfile.name : 'photo.jpg';
      final response = await _client.dio.post(
        ApiEndpoints.uploadPhoto,
        data: FormData.fromMap({
          'photo': MultipartFile.fromBytes(
            bytes,
            filename: filename,
            // The backend only accepts jpeg/png/webp; without an explicit
            // type dio sends application/octet-stream and it's rejected.
            contentType: _mediaTypeFor(filename),
          ),
        }),
      );
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(ProfilePhoto.fromJson(data));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  Future<ApiResult<void>> delete(String photoId) async {
    try {
      await _client.dio.delete(ApiEndpoints.deletePhoto(photoId));
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  Future<ApiResult<void>> setPrimary(String photoId) async {
    try {
      await _client.dio.put(ApiEndpoints.setPrimaryPhoto(photoId));
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  DioMediaType _mediaTypeFor(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return DioMediaType('image', 'png');
    if (lower.endsWith('.webp')) return DioMediaType('image', 'webp');
    return DioMediaType('image', 'jpeg');
  }
}

final profilePhotosRepositoryProvider = Provider<ApiProfilePhotosRepository>((ref) {
  return ApiProfilePhotosRepository(ref.watch(apiClientProvider));
});

/// The caller's stored photos, newest state straight from the backend.
final myPhotosProvider = FutureProvider.autoDispose<List<ProfilePhoto>>((ref) async {
  final result = await ref.watch(profilePhotosRepositoryProvider).list();
  return result.when(success: (data) => data, failure: (f) => throw f);
});
