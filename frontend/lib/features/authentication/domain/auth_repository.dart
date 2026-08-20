import '../../../core/api/api_result.dart';
import '../../../shared/models/user.dart';

abstract class AuthRepository {
  /// The returned String is the backend's `dev_otp` field — only ever
  /// non-null when the API is running with APP_ENV=dev (see
  /// internal/auth.Service.sendOTP on the backend; the field is entirely
  /// absent from the JSON body, not just empty, outside dev mode via its
  /// `omitempty` tag). Null in any real deployment.
  Future<ApiResult<String?>> requestOtp(String phoneOrEmail);
  Future<ApiResult<AppUser>> verifyOtp(String phoneOrEmail, String code);
  Future<ApiResult<String?>> resendOtp(String phoneOrEmail);

  /// Exchanges a Google-issued ID token for a real backend session. The
  /// backend verifies the token itself (signature, issuer, audience) —
  /// this call is only ever as trustworthy as that verification.
  Future<ApiResult<AppUser>> loginWithGoogle(String idToken);

  Future<ApiResult<void>> logout();
}
