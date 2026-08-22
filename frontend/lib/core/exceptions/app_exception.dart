/// Typed failure reasons surfaced to the UI layer. Repositories catch
/// transport-level errors (Dio, sockets, etc.) and normalize them into
/// one of these so screens never branch on raw exception types.
enum AppFailureType {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  validation,
  server,
  unknown,
  premiumRequired,
}

class AppFailure implements Exception {
  final AppFailureType type;
  final String message;
  final Map<String, String>? fieldErrors;

  /// The backend's machine-readable `error.code` (e.g. `already_registered`,
  /// `invalid_credentials`, `otp_not_found`), when the response carried one.
  /// Lets a screen branch on the specific error (switch to login mode, show
  /// a field-specific message) without parsing [message] text.
  final String? code;

  const AppFailure({
    required this.type,
    required this.message,
    this.fieldErrors,
    this.code,
  });

  factory AppFailure.network([String? message]) => AppFailure(
        type: AppFailureType.network,
        message: message ?? 'You appear to be offline. Check your connection and try again.',
      );

  factory AppFailure.timeout([String? message]) => AppFailure(
        type: AppFailureType.timeout,
        message: message ?? 'That took too long. Please try again.',
      );

  factory AppFailure.unauthorized([String? message]) => AppFailure(
        type: AppFailureType.unauthorized,
        message: message ?? 'Your session has expired. Please sign in again.',
      );

  factory AppFailure.validation(String message, [Map<String, String>? fields, String? code]) =>
      AppFailure(type: AppFailureType.validation, message: message, fieldErrors: fields, code: code);

  factory AppFailure.server([String? message]) => AppFailure(
        type: AppFailureType.server,
        message: message ?? 'Something went wrong on our end. Please try again shortly.',
      );

  factory AppFailure.unknown([String? message]) => AppFailure(
        type: AppFailureType.unknown,
        message: message ?? 'Something unexpected happened.',
      );

  factory AppFailure.premiumRequired([String? message]) => AppFailure(
        type: AppFailureType.premiumRequired,
        message: message ?? 'Upgrade to premium to send messages.',
      );

  @override
  String toString() => message;
}
