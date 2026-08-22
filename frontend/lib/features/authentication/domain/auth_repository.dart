import '../../../core/api/api_result.dart';
import '../../../shared/models/user.dart';

/// What a Google sign-in attempt resolved to. A returning, already-active
/// account signs straight in; a first-time signup (or one left pending by
/// an earlier, abandoned phone/email attempt for the same address) is
/// challenged with the same OTP every other signup path requires — Google
/// having verified the email address is not treated as a substitute for
/// that, only as proof the address is real.
sealed class GoogleAuthOutcome {
  const GoogleAuthOutcome();
}

class GoogleSignedIn extends GoogleAuthOutcome {
  final AppUser user;
  const GoogleSignedIn(this.user);
}

class GoogleOtpRequired extends GoogleAuthOutcome {
  /// The email address to verify — always the Google account's own
  /// email, and always what /auth/verify-otp needs as `identifier`.
  final String identifier;

  /// See AuthRepository.requestOtp's doc on the equivalent field: only
  /// ever non-null in dev.
  final String? devOtp;

  const GoogleOtpRequired(this.identifier, this.devOtp);
}

/// Mirrors `GET /users/me` — the account-level identifiers (as opposed to
/// profile fields), which is where phone/email actually live. A Google or
/// email signup starts with [phone] null; [requestLinkPhoneOtp]/
/// [AuthRepository.confirmLinkPhone] are how one gets attached afterward.
class AccountInfo {
  final String? phone;
  final String? email;

  const AccountInfo({this.phone, this.email});
}

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
  Future<ApiResult<GoogleAuthOutcome>> loginWithGoogle(String idToken);

  Future<ApiResult<void>> logout();

  /// Soft-deletes the signed-in account on the backend (blocks future
  /// login, revokes every session, hides the profile) and clears local
  /// session storage. There is no undo endpoint — callers must confirm
  /// with the user before calling this.
  Future<ApiResult<void>> deleteAccount();

  Future<ApiResult<AccountInfo>> getAccount();

  /// Sends an OTP to phone to attach it to the signed-in account. The
  /// returned String is the backend's dev_otp — same null-outside-dev
  /// contract as [requestOtp].
  Future<ApiResult<String?>> requestLinkPhoneOtp(String phone);

  /// Verifies the code [requestLinkPhoneOtp] sent and, on success,
  /// attaches phone to the signed-in account.
  Future<ApiResult<void>> confirmLinkPhone(String phone, String code);
}
