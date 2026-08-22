import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_result.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../core/notifications/push_notification_service.dart';
import '../../../../shared/models/user.dart';
import '../../data/api_auth_repository.dart';
import '../../data/google_auth_service.dart';
import '../../domain/auth_repository.dart';

class AuthState {
  final AppUser? user;
  final String? pendingContact;
  final bool isLoading;
  final AppFailure? failure;

  /// The backend's dev-only `dev_otp` echo from the most recent
  /// request-otp call — null in any real deployment (see
  /// AuthRepository.requestOtp's doc). The OTP screen shows this as a
  /// brief on-screen banner instead of a hardcoded demo string, purely so
  /// local testing doesn't need a real SMS provider; it never appears
  /// outside APP_ENV=dev because the backend never sends it outside that.
  final String? lastDevOtp;

  const AuthState({
    this.user,
    this.pendingContact,
    this.isLoading = false,
    this.failure,
    this.lastDevOtp,
  });

  AuthState copyWith({
    AppUser? user,
    String? pendingContact,
    bool? isLoading,
    AppFailure? failure,
    bool clearFailure = false,
    String? lastDevOtp,
    bool clearDevOtp = false,
  }) {
    return AuthState(
      user: user ?? this.user,
      pendingContact: pendingContact ?? this.pendingContact,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : failure ?? this.failure,
      lastDevOtp: clearDevOtp ? null : lastDevOtp ?? this.lastDevOtp,
    );
  }
}

/// What the caller of AuthController.signInWithGoogle should do next.
enum GoogleSignInResult { signedIn, otpRequired, cancelled, failed }

class AuthController extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final GoogleAuthService _googleAuth;
  final PushNotificationService _push;

  AuthController(this._repository, this._googleAuth, this._push) : super(const AuthState());

  Future<bool> requestOtp(String contact) async {
    state = state.copyWith(isLoading: true, clearFailure: true, clearDevOtp: true);
    final result = await _repository.requestOtp(contact);
    return result.when(
      success: (devOtp) {
        state = state.copyWith(
          isLoading: false,
          pendingContact: contact,
          lastDevOtp: devOtp,
          clearDevOtp: devOtp == null,
        );
        return true;
      },
      failure: (f) {
        state = state.copyWith(isLoading: false, failure: f);
        return false;
      },
    );
  }

  Future<bool> verifyOtp(String code) async {
    final contact = state.pendingContact;
    if (contact == null) return false;
    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await _repository.verifyOtp(contact, code);
    return result.when(
      success: (user) {
        state = state.copyWith(isLoading: false, user: user);
        // Registration is authenticated, so it can only run once a session
        // exists. Deliberately not awaited: a slow or failed push
        // registration must never hold up sign-in.
        unawaited(_push.registerDevice());
        return true;
      },
      failure: (f) {
        state = state.copyWith(isLoading: false, failure: f);
        return false;
      },
    );
  }

  /// Returns the raw result (rather than folding it into [state], the way
  /// [requestOtp]/[verifyOtp] do) so the OTP screen can show its own
  /// transient success/error feedback (e.g. a "Code resent" SnackBar plus
  /// a cooldown) without disturbing the shared isLoading/failure the
  /// Verify button already reads from this same state. Still updates
  /// [AuthState.lastDevOtp] on success, same as [requestOtp], so a resend
  /// refreshes the on-screen dev banner to the new code.
  Future<ApiResult<String?>> resendOtp() async {
    final contact = state.pendingContact;
    if (contact == null) {
      return ApiResult.failure(
        AppFailure.unknown('No pending verification to resend a code for.'),
      );
    }
    final result = await _repository.resendOtp(contact);
    result.when(
      success: (devOtp) => state = state.copyWith(lastDevOtp: devOtp, clearDevOtp: devOtp == null),
      failure: (_) {},
    );
    return result;
  }

  Future<bool> signup(String email, String password) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await _repository.signup(email, password);
    return result.when(
      success: (user) {
        state = state.copyWith(isLoading: false, user: user);
        unawaited(_push.registerDevice());
        return true;
      },
      failure: (f) {
        state = state.copyWith(isLoading: false, failure: f);
        return false;
      },
    );
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await _repository.login(email, password);
    return result.when(
      success: (user) {
        state = state.copyWith(isLoading: false, user: user);
        unawaited(_push.registerDevice());
        return true;
      },
      failure: (f) {
        state = state.copyWith(isLoading: false, failure: f);
        return false;
      },
    );
  }

  /// Kicks off the forgot-password flow. Always resolves true on a
  /// successful call (the backend always returns 200 regardless of whether
  /// the account exists), stashing [email] as pendingContact so
  /// [resetPassword] knows what to verify the code against.
  Future<bool> forgotPassword(String email) async {
    state = state.copyWith(isLoading: true, clearFailure: true, clearDevOtp: true);
    final result = await _repository.forgotPassword(email);
    return result.when(
      success: (devOtp) {
        state = state.copyWith(
          isLoading: false,
          pendingContact: email,
          lastDevOtp: devOtp,
          clearDevOtp: devOtp == null,
        );
        return true;
      },
      failure: (f) {
        state = state.copyWith(isLoading: false, failure: f);
        return false;
      },
    );
  }

  Future<bool> resetPassword(String code, String newPassword) async {
    final contact = state.pendingContact;
    if (contact == null) {
      state = state.copyWith(
        failure: AppFailure.unknown('Start the forgot-password flow again.'),
      );
      return false;
    }
    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await _repository.resetPassword(contact, code, newPassword);
    return result.when(
      success: (user) {
        state = state.copyWith(isLoading: false, user: user);
        unawaited(_push.registerDevice());
        return true;
      },
      failure: (f) {
        state = state.copyWith(isLoading: false, failure: f);
        return false;
      },
    );
  }

  /// Runs the real Google account picker, then exchanges the ID token it
  /// returns for a real backend session (the backend verifies the token
  /// itself — this app never trusts the picker result on its own).
  /// Returns GoogleSignInResult.cancelled if the user closes the picker
  /// with no error; check AuthState.failure for the message on .failed.
  Future<GoogleSignInResult> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    try {
      final account = await _googleAuth.signIn();
      if (account == null) {
        state = state.copyWith(isLoading: false);
        return GoogleSignInResult.cancelled;
      }

      final idToken = (await account.authentication).idToken;
      if (idToken == null) {
        state = state.copyWith(
          isLoading: false,
          failure: AppFailure.unknown('Google did not return a usable sign-in token.'),
        );
        return GoogleSignInResult.failed;
      }

      final result = await _repository.loginWithGoogle(idToken);
      return result.when(
        success: (outcome) => switch (outcome) {
          GoogleSignedIn(user: final user) => () {
              state = state.copyWith(isLoading: false, user: user);
              unawaited(_push.registerDevice());
              return GoogleSignInResult.signedIn;
            }(),
          // Same shape as any other pending signup: set pendingContact and
          // lastDevOtp exactly like requestOtp does, so the OTP screen and
          // its existing verifyOtp() call need no Google-specific branch --
          // this is a completely ordinary OTP verification from here on.
          GoogleOtpRequired(identifier: final identifier, devOtp: final devOtp) => () {
              state = state.copyWith(
                isLoading: false,
                pendingContact: identifier,
                lastDevOtp: devOtp,
                clearDevOtp: devOtp == null,
              );
              return GoogleSignInResult.otpRequired;
            }(),
        },
        failure: (f) {
          state = state.copyWith(isLoading: false, failure: f);
          return GoogleSignInResult.failed;
        },
      );
    } on GoogleAuthNotConfiguredException catch (e) {
      state = state.copyWith(
        isLoading: false,
        failure: AppFailure.unknown(
          "Google Sign-In isn't set up for this platform yet. ${e.details}",
        ),
      );
      return GoogleSignInResult.failed;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        failure: AppFailure.unknown('Google Sign-In failed. Please try again.'),
      );
      return GoogleSignInResult.failed;
    }
  }

  Future<void> signOut() async {
    // Must happen before logout clears the access token — the unregister
    // endpoint is authenticated. Otherwise this device keeps receiving the
    // signed-out account's notifications.
    await _push.unregisterDevice();
    await _repository.logout();
    await _googleAuth.signOut();
    state = const AuthState();
  }

  /// Deletes the signed-in account. Returns the failure, if any, so the
  /// settings screen can show it instead of assuming success; on success
  /// this also clears local session state exactly like [signOut].
  Future<AppFailure?> deleteAccount() async {
    final result = await _repository.deleteAccount();
    final failure = result.when(success: (_) => null, failure: (f) => f);
    if (failure != null) return failure;

    // Only unregister push once the account is actually gone — done
    // after, not before like signOut, since the delete call itself still
    // needs a valid session to authenticate.
    await _push.unregisterDevice();
    state = const AuthState();
    return null;
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.watch(authRepositoryProvider),
    ref.watch(googleAuthServiceProvider),
    ref.watch(pushNotificationServiceProvider),
  );
});
