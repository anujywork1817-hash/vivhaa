class AppRoutes {
  AppRoutes._();

  // Phase 1 — Onboarding & Registration
  static const String splash = '/';
  static const String authChoice = '/auth';
  static const String login = '/auth/login';
  static const String otp = '/auth/otp';

  static const String profileFor = '/onboarding/profile-for';
  static const String nameDob = '/onboarding/name-dob';
  static const String religionCommunity = '/onboarding/religion-community';
  static const String locationDetails = '/onboarding/location';
  static const String maritalHeightDiet = '/onboarding/marital-height-diet';
  static const String qualification = '/onboarding/qualification';
  static const String workDetails = '/onboarding/work-details';
  static const String aboutMe = '/onboarding/about-me';
  static const String photoUpload = '/onboarding/photo-upload';
  static const String verificationPrompt = '/onboarding/verification';
  static const String takeSelfie = '/onboarding/verification/selfie';
  static const String confirmSelfie = '/onboarding/verification/confirm';
  static const String verifying = '/onboarding/verification/verifying';
  static const String verificationInProgress = '/onboarding/verification/in-progress';
  static const String hobbies = '/onboarding/hobbies';
  static const String familyDetails = '/onboarding/family-details';
  static const String partnerPreferences = '/onboarding/partner-preferences';
  static const String connectMatches = '/onboarding/connect-matches';
  static const String premiumPaywall = '/onboarding/premium';
  static const String orderSummary = '/onboarding/order-summary';
  static const String reviewConfirm = '/onboarding/review';
  static const String welcomePending = '/onboarding/welcome';

  // Phase 2 — Core Navigation & Home
  static const String home = '/home';
  static const String notifications = '/home/notifications';
  static const String menu = '/home/menu';
  static const String favourites = '/home/favourites';
  static const String visitors = '/home/visitors';
  static const String blockedUsers = '/home/blocked-users';
  static const String editProfile = '/home/edit-profile';
  static const String managePhotos = '/home/edit-profile/photos';
  static const String accountSettings = '/home/account-settings';
  static const String preferences = '/home/preferences';
  static const String termsConditions = '/home/terms';
  static const String safetyTips = '/home/safety-tips';
  static const String aiAssistant = '/home/ai-assistant';
  static const String adminDashboard = '/admin';
  static const String adminUsers = '/admin/users';
  static const String adminVerifications = '/admin/verifications';
  static const String adminReports = '/admin/reports';

  // Phase 3 — Search & Discovery
  static const String basicSearch = '/search/basic';
  static const String advancedSearch = '/search/advanced';
  static const String searchResults = '/search/results';
  static const String savedSearches = '/search/saved';
  static const String searchByProfileId = '/search/profile-id';

  // Phase 4 — Profile Viewing & Interaction
  static const String discover = '/discover';
  static const String profileDetail = '/profile/:id';
  static const String photoGallery = '/profile/:id/photos';

  static String profileDetailPath(String id) => '/profile/$id';
  static String photoGalleryPath(String id) => '/profile/$id/photos';

  // Phase 5 — Communication
  static const String interests = '/interests';
  static const String interestDecision = '/interests/decision/:id';
  static const String chatWindow = '/chat/:id';

  static String interestDecisionPath(String interestId) => '/interests/decision/$interestId';
  static String chatWindowPath(String conversationId) => '/chat/$conversationId';
}
