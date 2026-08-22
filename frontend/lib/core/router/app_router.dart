import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/authentication/presentation/screens/auth_choice_screen.dart';
import '../../features/authentication/presentation/screens/forgot_password_screen.dart';
import '../../features/authentication/presentation/screens/otp_screen.dart';
import '../../features/authentication/presentation/screens/reset_password_screen.dart';
import '../../features/authentication/presentation/screens/splash_screen.dart';
import '../../features/calls/presentation/screens/call_history_screen.dart';
import '../../features/chat/presentation/screens/chat_window_screen.dart';
import '../../features/dashboard/presentation/screens/app_shell.dart';
import '../../features/discover_matches/presentation/screens/discover_screen.dart';
import '../../features/favourites/presentation/screens/favourites_screen.dart';
import '../../features/admin/presentation/screens/admin_dashboard_screen.dart';
import '../../features/admin/presentation/screens/admin_reports_screen.dart';
import '../../features/admin/presentation/screens/admin_users_screen.dart';
import '../../features/admin/presentation/screens/admin_verifications_screen.dart';
import '../../features/ai_chat/presentation/screens/ai_assistant_screen.dart';
import '../../features/blocked_users/presentation/screens/blocked_users_screen.dart';
import '../../features/edit_profile/presentation/screens/edit_profile_screen.dart';
import '../../features/edit_profile/presentation/screens/manage_photos_screen.dart';
import '../../features/settings/presentation/screens/account_settings_screen.dart';
import '../../features/settings/presentation/screens/preferences_screen.dart';
import '../../features/settings/presentation/screens/safety_tips_screen.dart';
import '../../features/settings/presentation/screens/terms_screen.dart';
import '../../features/profile_visitors/presentation/screens/visitors_screen.dart';
import '../../features/interests/presentation/screens/interest_decision_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/onboarding/presentation/screens/about_me_screen.dart';
import '../../features/onboarding/presentation/screens/connect_matches_screen.dart';
import '../../features/onboarding/presentation/screens/family_details_screen.dart';
import '../../features/onboarding/presentation/screens/hobbies_screen.dart';
import '../../features/onboarding/presentation/screens/location_screen.dart';
import '../../features/onboarding/presentation/screens/marital_height_diet_screen.dart';
import '../../features/onboarding/presentation/screens/name_dob_screen.dart';
import '../../features/onboarding/presentation/screens/partner_preferences_screen.dart';
import '../../features/onboarding/presentation/screens/photo_upload_screen.dart';
import '../../features/onboarding/presentation/screens/profile_for_screen.dart';
import '../../features/onboarding/presentation/screens/qualification_screen.dart';
import '../../features/onboarding/presentation/screens/religion_community_screen.dart';
import '../../features/onboarding/presentation/screens/review_confirm_screen.dart';
import '../../features/onboarding/presentation/screens/welcome_pending_screen.dart';
import '../../features/onboarding/presentation/screens/work_details_screen.dart';
import '../../features/premium/presentation/screens/order_summary_screen.dart';
import '../../features/premium/presentation/screens/premium_paywall_screen.dart';
import '../../features/profile/presentation/screens/menu_screen.dart';
import '../../features/profile_detail/presentation/screens/profile_detail_screen.dart';
import '../../shared/models/subscription_plan.dart';
import '../../features/verification/presentation/screens/confirm_selfie_screen.dart';
import '../../features/verification/presentation/screens/take_selfie_screen.dart';
import '../../features/verification/presentation/screens/verification_in_progress_screen.dart';
import '../../features/verification/presentation/screens/verification_prompt_screen.dart';
import '../../features/verification/presentation/screens/personal_document_upload_screen.dart';
import '../../features/verification/presentation/screens/verifying_screen.dart';
import '../../features/search/presentation/screens/advanced_search_screen.dart';
import '../../features/search/presentation/screens/basic_search_screen.dart';
import '../../features/search/presentation/screens/saved_searches_screen.dart';
import '../../features/search/presentation/screens/search_by_profile_id_screen.dart';
import '../../features/search/presentation/screens/search_results_screen.dart';
import 'app_routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: AppRoutes.authChoice, builder: (_, __) => const AuthChoiceScreen()),
      GoRoute(path: AppRoutes.otp, builder: (_, __) => const OtpScreen()),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, state) => ForgotPasswordScreen(initialEmail: state.extra as String?),
      ),
      GoRoute(path: AppRoutes.resetPassword, builder: (_, __) => const ResetPasswordScreen()),

      GoRoute(path: AppRoutes.profileFor, builder: (_, __) => const ProfileForScreen()),
      GoRoute(path: AppRoutes.nameDob, builder: (_, __) => const NameDobScreen()),
      GoRoute(
          path: AppRoutes.religionCommunity,
          builder: (_, __) => const ReligionCommunityScreen()),
      GoRoute(path: AppRoutes.locationDetails, builder: (_, __) => const LocationScreen()),
      GoRoute(
          path: AppRoutes.maritalHeightDiet,
          builder: (_, __) => const MaritalHeightDietScreen()),
      GoRoute(path: AppRoutes.qualification, builder: (_, __) => const QualificationScreen()),
      GoRoute(path: AppRoutes.workDetails, builder: (_, __) => const WorkDetailsScreen()),
      GoRoute(path: AppRoutes.aboutMe, builder: (_, __) => const AboutMeScreen()),
      GoRoute(path: AppRoutes.photoUpload, builder: (_, __) => const PhotoUploadScreen()),
      GoRoute(
          path: AppRoutes.verificationPrompt,
          builder: (_, __) => const VerificationPromptScreen()),
      GoRoute(path: AppRoutes.takeSelfie, builder: (_, __) => const TakeSelfieScreen()),
      GoRoute(path: AppRoutes.confirmSelfie, builder: (_, __) => const ConfirmSelfieScreen()),
      GoRoute(path: AppRoutes.verifying, builder: (_, __) => const VerifyingScreen()),
      GoRoute(
          path: AppRoutes.verificationInProgress,
          builder: (_, __) => const VerificationInProgressScreen()),
      GoRoute(
          path: AppRoutes.personalDocumentUpload,
          builder: (_, __) => const PersonalDocumentUploadScreen()),
      GoRoute(
          path: AppRoutes.hobbies,
          builder: (_, state) => HobbiesScreen(standalone: state.extra == true)),
      GoRoute(path: AppRoutes.familyDetails, builder: (_, __) => const FamilyDetailsScreen()),
      GoRoute(
          path: AppRoutes.partnerPreferences,
          builder: (_, state) =>
              PartnerPreferencesScreen(standalone: state.extra == true)),
      GoRoute(path: AppRoutes.connectMatches, builder: (_, __) => const ConnectMatchesScreen()),
      GoRoute(
          path: AppRoutes.premiumPaywall,
          builder: (_, state) => PremiumPaywallScreen(forceShowPlans: state.extra == true)),
      GoRoute(
        path: AppRoutes.orderSummary,
        // BUG-H04: `extra` is never serialized — a deep link, a process
        // restart that restores navigation state, or any other path that
        // reaches this route without going through the paywall's own
        // push (the only call site that sets it) arrives with extra
        // null, and the old `as SubscriptionPlan` crashed outright.
        // Falling back to the plan picker is recoverable; a hard crash
        // was not.
        builder: (_, state) {
          final plan = state.extra;
          if (plan is! SubscriptionPlan) return const PremiumPaywallScreen();
          return OrderSummaryScreen(plan: plan);
        },
      ),
      GoRoute(path: AppRoutes.reviewConfirm, builder: (_, __) => const ReviewConfirmScreen()),
      GoRoute(path: AppRoutes.welcomePending, builder: (_, __) => const WelcomePendingScreen()),

      GoRoute(path: AppRoutes.home, builder: (_, __) => const AppShell()),
      GoRoute(path: AppRoutes.notifications, builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: AppRoutes.menu, builder: (_, __) => const MenuScreen()),
      GoRoute(path: AppRoutes.favourites, builder: (_, __) => const FavouritesScreen()),
      GoRoute(path: AppRoutes.visitors, builder: (_, __) => const VisitorsScreen()),
      GoRoute(path: AppRoutes.blockedUsers, builder: (_, __) => const BlockedUsersScreen()),
      GoRoute(path: AppRoutes.editProfile, builder: (_, __) => const EditProfileScreen()),
      GoRoute(path: AppRoutes.managePhotos, builder: (_, __) => const ManagePhotosScreen()),
      GoRoute(path: AppRoutes.accountSettings, builder: (_, __) => const AccountSettingsScreen()),
      GoRoute(path: AppRoutes.preferences, builder: (_, __) => const PreferencesScreen()),
      GoRoute(path: AppRoutes.termsConditions, builder: (_, __) => const TermsScreen()),
      GoRoute(path: AppRoutes.safetyTips, builder: (_, __) => const SafetyTipsScreen()),
      GoRoute(path: AppRoutes.aiAssistant, builder: (_, __) => const AiAssistantScreen()),
      GoRoute(path: AppRoutes.adminDashboard, builder: (_, __) => const AdminDashboardScreen()),
      GoRoute(path: AppRoutes.adminUsers, builder: (_, __) => const AdminUsersScreen()),
      GoRoute(path: AppRoutes.adminVerifications, builder: (_, __) => const AdminVerificationsScreen()),
      GoRoute(path: AppRoutes.adminReports, builder: (_, __) => const AdminReportsScreen()),

      GoRoute(path: AppRoutes.basicSearch, builder: (_, __) => const BasicSearchScreen()),
      GoRoute(path: AppRoutes.advancedSearch, builder: (_, __) => const AdvancedSearchScreen()),
      GoRoute(path: AppRoutes.searchResults, builder: (_, __) => const SearchResultsScreen()),
      GoRoute(path: AppRoutes.savedSearches, builder: (_, __) => const SavedSearchesScreen()),
      GoRoute(
          path: AppRoutes.searchByProfileId,
          builder: (_, __) => const SearchByProfileIdScreen()),

      GoRoute(path: AppRoutes.discover, builder: (_, __) => const DiscoverScreen()),
      GoRoute(
        path: AppRoutes.profileDetail,
        builder: (_, state) =>
            ProfileDetailScreen(profileId: state.pathParameters['id']!),
      ),

      GoRoute(
        path: AppRoutes.interestDecision,
        builder: (_, state) =>
            InterestDecisionScreen(interestId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.chatWindow,
        builder: (_, state) =>
            ChatWindowScreen(conversationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.callHistory,
        builder: (_, __) => const CallHistoryScreen(),
      ),
    ],
  );
});
