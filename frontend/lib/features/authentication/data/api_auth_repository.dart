import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../shared/models/user.dart';
import '../domain/auth_repository.dart';

/// Talks to the real matrimony_backend `/auth/*` endpoints. Passwordless
/// only: [requestOtp] covers both signup and login (the backend infers
/// which one applies from whether the identifier already has an active
/// account), and [verifyOtp] auto-logs-in on success either way.
class ApiAuthRepository implements AuthRepository {
  final ApiClient _client;
  final SecureStorageService _storage;

  ApiAuthRepository(this._client, this._storage);

  @override
  Future<ApiResult<String?>> requestOtp(String phoneOrEmail) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.requestOtp,
        data: {'identifier': phoneOrEmail},
      );
      final data = response.data['data'] as Map<String, dynamic>?;
      return ApiResult.success(data?['dev_otp'] as String?);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<String?>> resendOtp(String phoneOrEmail) => requestOtp(phoneOrEmail);

  @override
  Future<ApiResult<AppUser>> verifyOtp(String phoneOrEmail, String code) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.verifyOtp,
        data: {'identifier': phoneOrEmail, 'code': code},
      );
      return await _completeLogin(response, fallbackIdentifier: phoneOrEmail);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<GoogleAuthOutcome>> loginWithGoogle(String idToken) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.googleAuth,
        data: {'id_token': idToken},
      );
      final data = response.data['data'] as Map<String, dynamic>;

      if (data['otp_required'] == true) {
        return ApiResult.success(GoogleOtpRequired(
          data['identifier'] as String,
          data['dev_otp'] as String?,
        ));
      }

      final loggedIn = await _completeLogin(response);
      return loggedIn.when(
        success: (user) => ApiResult.success(GoogleSignedIn(user)),
        failure: (f) => ApiResult.failure(f),
      );
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  /// Shared tail of every login path (OTP or Google): persist the token
  /// pair and build the [AppUser] the rest of the app works with.
  Future<ApiResult<AppUser>> _completeLogin(Response response, {String? fallbackIdentifier}) async {
    final data = response.data['data'] as Map<String, dynamic>;

    final accessToken = data['access_token'] as String;
    final refreshToken = data['refresh_token'] as String;
    await _storage.writeTokens(accessToken: accessToken, refreshToken: refreshToken);

    final user = data['user'] as Map<String, dynamic>;
    final identifier = (user['email'] as String?) ?? (user['phone'] as String?) ?? fallbackIdentifier ?? '';

    return ApiResult.success(AppUser(
      id: user['id'] as String,
      phoneOrEmail: identifier,
      otpVerified: true,
      // The backend has no "profile complete" concept on the user
      // record itself — GET /profiles/me 404ing is what actually means
      // "no profile yet". Callers that need this signal should check
      // that separately rather than trust this hardcoded false.
      profileComplete: false,
      createdAt: DateTime.now(),
      role: user['role'] as String? ?? 'user',
    ));
  }

  @override
  Future<ApiResult<void>> logout() async {
    try {
      final refreshToken = await _storage.readRefreshToken();
      if (refreshToken != null) {
        await _client.dio.post(
          ApiEndpoints.logout,
          data: {'refresh_token': refreshToken},
        );
      }
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    } finally {
      await _storage.clear();
    }
  }

  @override
  Future<ApiResult<void>> deleteAccount() async {
    try {
      await _client.dio.delete(ApiEndpoints.deleteAccount);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
    // Only clear local session once the account is confirmed gone — on
    // failure the account still exists and the user should be able to
    // retry, not find themselves silently signed out.
    await _storage.clear();
    return const ApiResult.success(null);
  }

  @override
  Future<ApiResult<AccountInfo>> getAccount() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.myAccount);
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(AccountInfo(
        phone: data['phone'] as String?,
        email: data['email'] as String?,
      ));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<String?>> requestLinkPhoneOtp(String phone) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.linkPhoneRequestOtp,
        data: {'phone': phone},
      );
      final data = response.data['data'] as Map<String, dynamic>?;
      return ApiResult.success(data?['dev_otp'] as String?);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> confirmLinkPhone(String phone, String code) async {
    try {
      await _client.dio.post(
        ApiEndpoints.linkPhoneVerify,
        data: {'phone': phone, 'code': code},
      );
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return ApiAuthRepository(ref.watch(apiClientProvider), ref.watch(secureStorageServiceProvider));
});
