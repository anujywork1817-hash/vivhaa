import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Central endpoint registry, matched to the actual matrimony_backend
/// Go API (see that project's docs/postman_phase*.json for the full
/// contract). Paths and the response envelope ({success, data, error,
/// meta}) are backend-specific — this file is the one place that
/// mapping lives, so a backend URL/path change never touches a screen.
class ApiEndpoints {
  ApiEndpoints._();

  /// Defaults to the dev machine's LAN IP for Android — this project is
  /// being tested on a real physical device over WiFi, not the emulator
  /// (which would instead need 10.0.2.2). iOS simulator, web, and desktop
  /// all reach the backend via localhost directly.
  ///
  /// If the dev machine's LAN IP ever changes (new network, DHCP lease
  /// renewal, etc.), update _devMachineLanIp below, or override per-run
  /// with --dart-define=API_BASE_URL=http://<ip>:58080 without touching
  /// this file (e.g. --dart-define=API_BASE_URL=http://10.0.2.2:58080
  /// to target the emulator instead).
  static const String _devMachineLanIp = '192.168.1.7';

  static String get baseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    if (!kIsWeb && Platform.isAndroid) return 'http://$_devMachineLanIp:8080';
    return 'http://localhost:8080';
  }

  static String get wsBaseUrl {
    const override = String.fromEnvironment('WS_BASE_URL');
    if (override.isNotEmpty) return override;
    if (!kIsWeb && Platform.isAndroid) return 'ws://$_devMachineLanIp:8080';
    return 'ws://localhost:8080';
  }

  // Auth — passwordless, single request-otp entry point for both new and
  // returning users (see internal/auth.Service.RequestOTP on the backend).
  static const String requestOtp = '/auth/request-otp';
  static const String verifyOtp = '/auth/verify-otp';
  static const String googleAuth = '/auth/google';
  static const String refreshToken = '/auth/refresh-token';
  static const String logout = '/auth/logout';

  static const String myProfile = '/profiles/me';
  static const String createProfile = '/profiles';
  static String profileById(String id) => '/profiles/$id';
  static String profileByCode(String code) => '/profile-code/$code';
  static String profileContact(String id) => '/profiles/$id/contact';
  static const String partnerPreferences = '/preferences';
  static const String uploadPhoto = '/profiles/me/photos';
  static String setPrimaryPhoto(String photoId) => '/profiles/me/photos/$photoId/primary';
  static String deletePhoto(String photoId) => '/profiles/me/photos/$photoId';

  static const String dailyMatches = '/matches/daily';
  static const String recommendedMatches = '/matches/recommended';
  static const String allMatches = '/matches/all';
  static const String nearbyMatches = '/matches/nearby';
  static const String updateLocation = '/profiles/me/location';
  static const String search = '/search/profiles';
  static const String savedSearches = '/saved-searches';
  static String savedSearch(String id) => '/saved-searches/$id';

  static String expressInterest(String profileId) => '/interests/$profileId';
  static String acceptInterest(String interestId) => '/interests/$interestId/accept';
  static String declineInterest(String interestId) => '/interests/$interestId/decline';
  static String deleteInterest(String interestId) => '/interests/$interestId';
  static String remindInterest(String interestId) => '/interests/$interestId/remind';
  static const String interestsSent = '/interests/sent';
  static const String interestsReceived = '/interests/received';
  static const String interestsDeleted = '/interests/deleted';

  static String favourite(String profileId) => '/favourites/$profileId';
  static const String favourites = '/favourites';
  static String shortlist(String profileId) => '/shortlisted/$profileId';
  static const String shortlisted = '/shortlisted';
  static const String visitors = '/visitors';
  static String blockUser(String profileId) => '/blocked/$profileId';
  static const String blocked = '/blocked';

  static const String conversations = '/chat/conversations';
  static String messages(String userId) => '/chat/messages/$userId';
  static String requestContact(String userId) => '/chat/messages/$userId/contact-request';
  static String acceptContact(String messageId) => '/chat/contact-requests/$messageId/accept';
  static String declineContact(String messageId) => '/chat/contact-requests/$messageId/decline';
  static const String wsChat = '/ws/chat';
  static const String iceServers = '/video-call/ice-servers';

  static const String subscriptionPlans = '/subscriptions/plans';
  static const String mySubscription = '/subscriptions/me';
  static const String paymentsCheckout = '/payments/checkout';
  static const String paymentsVerify = '/payments/verify';
  static const String paymentHistory = '/payments/history';

  static const String deviceToken = '/devices/token';

  static const String notifications = '/notifications';
  static const String notificationsReadAll = '/notifications/read-all';
  static String notificationRead(String id) => '/notifications/$id/read';

  static const String aiChat = '/ai/chat';
  static const String aiMessages = '/ai/messages';
  static String aiIcebreakers(String profileId) => '/ai/icebreakers/$profileId';
  static String aiMatchBlurb(String profileId) => '/ai/match-blurb/$profileId';

  static const String adminDashboard = '/admin/dashboard';
  static const String adminUsers = '/admin/users';
  static String adminUser(String id) => '/admin/users/$id';
  static String adminSuspendUser(String id) => '/admin/users/$id/suspend';
  static String adminActivateUser(String id) => '/admin/users/$id/activate';
  static const String adminVerifications = '/admin/verifications';
  static String adminApproveVerification(String id) => '/admin/verifications/$id/approve';
  static String adminRejectVerification(String id) => '/admin/verifications/$id/reject';
  static const String adminReports = '/admin/reports';
  static String adminResolveReport(String id) => '/admin/reports/$id/resolve';

  // Reference lists (countries/states/cities and the religion tree) — these
  // used to be hardcoded Dart constants per screen; the backend now owns
  // them so they cascade off real data and change without an app release.
  static const String referenceCountries = '/reference/countries';
  static const String referenceReligions = '/reference/religions';
  static String referenceStates(String countryCode) =>
      '/reference/countries/$countryCode/states';
  static String referenceCities(String countryCode, String stateCode) =>
      '/reference/countries/$countryCode/states/$stateCode/cities';

  static String reportUser(String profileId) => '/reports/$profileId';
  static const String verificationSubmit = '/verification/id';
  static const String verificationStatus = '/verification/me';
  static const String verificationMine = '/verification/me/all';
}
