import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../shared/models/partner_preferences.dart';
import '../../../../shared/models/profile.dart';
import '../../data/api_onboarding_repository.dart';
import '../../domain/onboarding_repository.dart';

/// Total steps in the profile-creation flow. The welcome screen isn't a
/// form step, so it's excluded from the count shown in
/// [OnboardingStepScaffold].
const int onboardingStepCount = 9;

class ProfileCreationState {
  final Profile draft;
  final bool submitting;
  final AppFailure? failure;

  /// Photos that couldn't be uploaded on the last submit, even though the
  /// profile itself saved — surfaced separately so the user is told their
  /// photo didn't save instead of it silently vanishing.
  final int photoUploadFailures;

  const ProfileCreationState({
    required this.draft,
    this.submitting = false,
    this.failure,
    this.photoUploadFailures = 0,
  });

  ProfileCreationState copyWith({
    Profile? draft,
    bool? submitting,
    AppFailure? failure,
    int? photoUploadFailures,
  }) {
    return ProfileCreationState(
      draft: draft ?? this.draft,
      submitting: submitting ?? this.submitting,
      failure: failure,
      photoUploadFailures: photoUploadFailures ?? this.photoUploadFailures,
    );
  }
}

class ProfileCreationController extends StateNotifier<ProfileCreationState> {
  final OnboardingRepository _repository;

  ProfileCreationController(this._repository)
      : super(ProfileCreationState(draft: const Profile()));

  void update(Profile Function(Profile current) updater) {
    state = state.copyWith(draft: updater(state.draft));
  }

  void updatePartnerPreferences(PartnerPreferences Function(PartnerPreferences current) updater) {
    state = state.copyWith(
      draft: state.draft.copyWith(partnerPreferences: updater(state.draft.partnerPreferences)),
    );
  }

  Future<bool> submit() async {
    state = state.copyWith(submitting: true, failure: null, photoUploadFailures: 0);
    final result = await _repository.submitProfile(state.draft);
    return result.when(
      success: (submitted) {
        state = state.copyWith(
          draft: submitted.profile,
          submitting: false,
          photoUploadFailures: submitted.photoUploadFailures,
        );
        return true;
      },
      failure: (f) {
        state = state.copyWith(submitting: false, failure: f);
        return false;
      },
    );
  }

  void reset() {
    state = ProfileCreationState(draft: const Profile());
  }

  /// Fetches the caller's existing backend profile, if any, and hydrates
  /// the draft with it. Returns true when a profile was found — callers
  /// use that to decide whether to skip onboarding entirely. Safe to call
  /// repeatedly (e.g. once per login and once per app-shell mount).
  Future<bool> loadExisting() async {
    final result = await _repository.getMyProfile();
    return result.when(
      success: (profile) {
        if (profile == null) return false;
        state = state.copyWith(draft: profile);
        return true;
      },
      failure: (_) => false,
    );
  }
}

final profileCreationControllerProvider =
    StateNotifierProvider<ProfileCreationController, ProfileCreationState>((ref) {
  return ProfileCreationController(ref.watch(onboardingRepositoryProvider));
});
