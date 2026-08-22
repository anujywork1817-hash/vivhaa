import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../shared/models/interest.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../chat/data/chat_socket_service.dart';
import '../../../chat/presentation/controllers/chat_controller.dart';
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

/// The sent-interest record for this profile, if any — lets a screen that
/// only knows the profile id (not the interest id) still offer to withdraw
/// it, without a separate lookup round trip.
final sentInterestForProfileProvider =
    Provider.autoDispose.family<InterestRecord?, String>((ref, profileId) {
  final sent = ref.watch(sentInterestsProvider).valueOrNull ?? const [];
  for (final r in sent) {
    if (r.profile.id == profileId) return r;
  }
  return null;
});

/// The partner's user id when this profile is an accepted match in either
/// direction, else null — i.e. "can I chat with them, and where".
///
/// Chat entry points used to test the conversation list instead, which only
/// works once that list has loaded *and* its profile-id mapping resolved. The
/// interest's own status is the authority on whether chat is unlocked, so
/// screens can offer it the instant an accept lands.
final acceptedPartnerUserIdProvider =
    Provider.autoDispose.family<String?, String>((ref, profileId) {
  final records = [
    ...ref.watch(receivedInterestsProvider).valueOrNull ?? const [],
    ...ref.watch(sentInterestsProvider).valueOrNull ?? const [],
  ];
  for (final r in records) {
    if (r.profile.id == profileId && r.status == InterestStatus.accepted) {
      return r.partnerUserId;
    }
  }
  return null;
});

final pendingReceivedCountProvider = Provider.autoDispose<int>((ref) {
  final received = ref.watch(receivedInterestsProvider).valueOrNull ?? const [];
  return received.where((r) => r.status == InterestStatus.pending).length;
});

class InterestsActions {
  final Ref ref;
  InterestsActions(this.ref);

  // BUG-M06: this discarded the ApiResult entirely, so a failed send
  // (rate limited, already interested, blocked) was indistinguishable
  // from success at every call site — two of them show "Interest sent"
  // unconditionally right after awaiting this. Returning the failure (or
  // null on success), same as withdraw() below, lets callers actually
  // branch on the outcome.
  Future<AppFailure?> send(MatchProfile profile) async {
    final result = await ref.read(interestRepositoryProvider).sendInterest(profile);
    ref.invalidate(sentInterestsProvider);
    return result.when(success: (_) => null, failure: (f) => f);
  }

  /// Accepting unlocks chat on the backend immediately, so the conversation
  /// list is refreshed here too. Without that, the thread only appeared
  /// after a manual pull-to-refresh, which made a freshly accepted match
  /// look like chat still wasn't available.
  Future<void> respond(String interestId, bool accept) async {
    await ref.read(interestRepositoryProvider).respond(interestId, accept);
    ref.invalidate(receivedInterestsProvider);
    if (accept) ref.invalidate(conversationsProvider);
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

/// Keeps both parties' interest and conversation lists current the moment an
/// interest is sent or accepted.
///
/// The accepter refreshes their own lists in [InterestsActions.respond], but
/// the *sender* has no idea it happened — they used to sit on a stale screen
/// until they pulled to refresh. The backend pushes `interest_accepted` down
/// the chat socket to both sides; this turns that into a refresh wherever the
/// user happens to be in the app. Likewise, the *receiver* of a brand-new
/// interest used to only find out via the persisted notifications list (or
/// push, if configured) — `interest_received` gets the same live-refresh
/// treatment so it shows up on the Interests tab immediately instead of
/// waiting on a manual pull-to-refresh.
///
/// Deliberately not autoDispose, and watched by the app shell rather than one
/// screen: the point is that it works while the user is anywhere.
final matchLiveUpdatesProvider = Provider<void>((ref) {
  final subscription = ref.watch(chatSocketServiceProvider).events.listen((event) {
    switch (event['type']) {
      case 'interest_accepted':
        ref.invalidate(conversationsProvider);
        ref.invalidate(receivedInterestsProvider);
        ref.invalidate(sentInterestsProvider);
      case 'interest_received':
        ref.invalidate(receivedInterestsProvider);
    }
  });
  ref.onDispose(subscription.cancel);
});
