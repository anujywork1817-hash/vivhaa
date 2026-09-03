import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../router/app_router.dart';
import '../router/app_routes.dart';
import '../storage/secure_storage_service.dart';
import 'api_endpoints.dart';

/// Thin Dio wrapper with auth-header injection and 401 refresh handling.
/// Response envelope is the backend's `{success, data, error, meta}` —
/// repositories read `response.data['data']`, not `response.data` itself.
class ApiClient {
  final Dio dio;
  final SecureStorageService _storage;
  final Ref _ref;

  /// Separate, interceptor-free client for the refresh call itself —
  /// using [dio] here would recurse back into onError if refresh-token
  /// ever returns 401.
  final Dio _refreshDio;

  ApiClient(this._storage, this._ref)
      : dio = Dio(BaseOptions(
          baseUrl: ApiEndpoints.baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Content-Type': 'application/json'},
        )),
        _refreshDio = Dio(BaseOptions(
          baseUrl: ApiEndpoints.baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Content-Type': 'application/json'},
        )) {
    dio.interceptors.addAll([
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.readAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final isAuthEndpoint = error.requestOptions.path == ApiEndpoints.refreshToken ||
              error.requestOptions.path == ApiEndpoints.verifyOtp;
          if (error.response?.statusCode == 401 && !isAuthEndpoint) {
            final refreshed = await _tryRefreshToken();
            if (refreshed) {
              final clone = await _retry(error.requestOptions);
              return handler.resolve(clone);
            }
            await _storage.clear();
          }
          // Global "hook then pay ₹1" redirect: middleware.RequireUnlocked
          // gates every real feature behind this 402 (see backend
          // internal/middleware/unlock.go), and it can come back from any
          // screen — the dashboard's own "Couldn't load matches" fallback,
          // search, chat, calls, wherever. Previously nothing actually
          // listened for AppFailureType.unlockRequired outside the paywall
          // screen itself, so every one of those screens just showed its
          // own generic error text instead of ever taking the user to the
          // one place (UnlockPaywallScreen) that can fix it. Handled here,
          // once, for every request this client makes, rather than
          // re-litigating it in each screen's error branch.
          if (error.response?.statusCode == 402 &&
              _extractErrorCode(error.response?.data) == 'unlock_required') {
            _ref.read(appRouterProvider).go(AppRoutes.unlockPaywall);
          }
          handler.next(error);
        },
      ),
      // Debug-only (see BUG-H02 — release builds never log at all, so a
      // real device's system log never sees any of this). Headers are off
      // even here: LogInterceptor's default requestHeader/responseHeader
      // would print the Authorization: Bearer <token> this client injects
      // above into the local dev console on every single request, which
      // is a live, replayable credential sitting in plain text — not
      // something worth trading for convenience, even on a dev machine.
      if (kDebugMode)
        LogInterceptor(
          requestBody: false,
          responseBody: false,
          requestHeader: false,
          responseHeader: false,
        ),
    ]);
  }

  /// Refresh in flight, if any — every concurrent 401 awaits this same
  /// future instead of starting its own refresh call.
  Future<bool>? _refreshInFlight;

  /// Single-flights the refresh call (BUG-H01): a burst of simultaneous
  /// requests can all get a 401 back at once (e.g. right as the access
  /// token expires), and without de-duplication each one independently
  /// calls this method. If the backend rotates refresh tokens (issues a
  /// new one and invalidates the old on every use — see
  /// pkg/jwt.Issuer/POST /auth/refresh-token), only the first of those
  /// concurrent calls succeeds; every other one is racing with an
  /// already-consumed refresh token and fails, which previously meant
  /// _storage.clear() ran and the user was logged out — despite having a
  /// perfectly valid session a moment earlier.
  Future<bool> _tryRefreshToken() {
    return _refreshInFlight ??= _refreshTokenOnce().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _refreshTokenOnce() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) return false;
    try {
      final response = await _refreshDio.post(
        ApiEndpoints.refreshToken,
        data: {'refresh_token': refreshToken},
      );
      final data = response.data?['data'] as Map<String, dynamic>?;
      final newAccess = data?['access_token'] as String?;
      final newRefresh = data?['refresh_token'] as String?;
      if (newAccess == null || newRefresh == null) return false;
      await _storage.writeTokens(accessToken: newAccess, refreshToken: newRefresh);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions requestOptions) {
    final options = Options(method: requestOptions.method, headers: requestOptions.headers);
    return dio.request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }
}

/// Reads the backend's `{success:false, error:{code, ...}}` envelope —
/// mirrors api_error_mapper.dart's private `_extractCode`, duplicated
/// rather than shared since that one lives alongside DioException-specific
/// mapping this interceptor doesn't otherwise need.
String? _extractErrorCode(dynamic body) {
  if (body is Map && body['error'] is Map) {
    final code = body['error']['code'];
    if (code is String) return code;
  }
  return null;
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(secureStorageServiceProvider), ref);
});
