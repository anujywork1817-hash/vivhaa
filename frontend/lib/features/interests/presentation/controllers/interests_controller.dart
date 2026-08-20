import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../shared/models/interest.dart';
import '../../../../shared/models/match_profile.dart';
import '../../data/api_interest_repository.dart';

final sentInterestsProvider = FutureProvider.autoDispose<List<InterestRecord>>((ref) async {
  final result = await ref.watch(interestRepositoryProvider).getSent();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

final deletedInterestsProvider = FutureProvider.autoDispose<List<InterestRecord>>((ref) async {
  final result = await ref.watch(interestRepositoryProvider).getDeleted();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

final receivedInterestsProvider = FutureProvider.autoDispose<List<InterestRecord>>((ref) async {
  final result = await ref.watch(interestRepositoryProvider).getReceived();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

/// True once an interest has been sent to this profile, so profile
/// detail / the swipe deck can show "Interest Sent" without waiting on
/// a fresh fetch after the action completes.
final isInterestSentProvider = Provider.autoDispose.family<bool, String>((ref, profileId) {
  final sent = ref.watch(sentInterestsProvider).valueOrNull ?? const [];
  return sent.any((r) => r.profile.id == profileId);
});

final pendingReceivedCountProvider = Provider.autoDispose<int>((ref) {
  final received = ref.watch(receivedInterestsProvider).valueOrNull ?? const [];
  return received.where((r) => r.status == InterestStatus.pending).length;
});

class InterestsActions {
  final Ref ref;
  InterestsActions(this.ref);

  Future<void> send(MatchProfile profile) async {
    await ref.read(interestRepositoryProvider).sendInterest(profile);
    ref.invalidate(sentInterestsProvider);
  }

  Future<void> respond(String interestId, bool accept) async {
    await ref.read(interestRepositoryProvider).respond(interestId, accept);
    ref.invalidate(receivedInterestsProvider);
  }

  /// Deletes an interest in either direction, so both lists are refreshed
  /// (a received request can be cleared from the inbox too, not just a
  /// sent one withdrawn). Returns the failure, if any, so the caller can
  /// tell the user rather than silently appearing to succeed.
  Future<AppFailure?> withdraw(String interestId) async {
    final result = await ref.read(interestRepositoryProvider).withdraw(interestId);
    ref.invalidate(sentInterestsProvider);
    ref.invalidate(receivedInterestsProvider);
    ref.invalidate(deletedInterestsProvider);
    return result.when(success: (_) => null, failure: (f) => f);
  }

  Future<AppFailure?> remind(String interestId) async {
    final result = await ref.read(interestRepositoryProvider).remind(interestId);
    return result.when(success: (_) => null, failure: (f) => f);
  }
}

final interestsActionsProvider = Provider((ref) => InterestsActions(ref));
