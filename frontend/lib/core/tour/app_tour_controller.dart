import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the new-user coach-mark walkthrough (see
/// AppShellTourKeys below) has already auto-played once for a given
/// account, so it never interrupts the Dashboard again after the first
/// successful run — mirrors [AppRatingController]'s use of a
/// SharedPreferences flag, but exposes one-shot read/write methods instead
/// of a reactive [StateNotifier] since the Dashboard only ever needs the
/// answer once, at its first frame, and awaiting a provider's async load
/// would risk a race between "has the flag loaded yet" and "have we
/// already rendered the first frame".
///
/// Keyed per user id rather than one flag for the whole device/install: a
/// device can be signed out of and back into with a different account
/// (family sharing a phone, testing multiple profiles), and each of those
/// logins is that account's own "first time" — a single global flag would
/// wrongly skip the tour for every account after whichever one saw it
/// first.
class AppTourController {
  static const _hasSeenTourKeyPrefix = 'has_seen_app_tour_';

  Future<bool> hasSeenTour(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_hasSeenTourKeyPrefix$userId') ?? false;
  }

  Future<void> markSeen(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_hasSeenTourKeyPrefix$userId', true);
  }
}

final appTourControllerProvider = Provider<AppTourController>((ref) {
  return AppTourController();
});

/// Set to `true` by the "Take a Tour" row in the hamburger menu right
/// before navigating back to Home, so HomeDashboardScreen (already mounted
/// and alive inside AppShell's IndexedStack, so its own initState never
/// re-runs) knows to replay the walkthrough on its next build even though
/// the first-time auto-trigger has long since fired. HomeDashboardScreen
/// resets this back to `false` once it has acted on it.
final tourReplayRequestedProvider = StateProvider<bool>((ref) => false);

/// True for as long as the walkthrough is actually on screen — set when
/// HomeDashboardScreen calls startShowCase, cleared either by
/// ShowCaseWidget's onFinish (see app.dart, the natural "completed every
/// step" path) or directly alongside a manual ShowCaseWidget.dismiss()
/// call (dismiss() does NOT invoke onFinish, so a Skip action has to clear
/// this itself). Drives whether the floating Skip button renders.
final tourActiveProvider = StateProvider<bool>((ref) => false);

/// The GlobalKeys every Showcase step in the walkthrough is registered
/// under, shared between HomeDashboardScreen (AppBar: menu, avatar, bell,
/// search bar) and AppShell (bottom-nav tabs) — the two widgets that
/// together make up the tour. Kept as a single long-lived instance (via a
/// plain, non-autoDispose Provider) rather than created fresh in each
/// widget's build, since ShowCaseWidget.startShowCase needs the very same
/// key instances that are actually attached in the widget tree.
class AppShellTourKeys {
  final menu = GlobalKey();
  final avatar = GlobalKey();
  final notifications = GlobalKey();
  final search = GlobalKey();
  final matchesTab = GlobalKey();
  final inboxTab = GlobalKey();
  final chatTab = GlobalKey();
  final premiumTab = GlobalKey();

  /// The full walkthrough, in the order it should play. All of these
  /// widgets are mounted simultaneously once AppShell has built once,
  /// since AppShell keeps every tab alive via IndexedStack rather than
  /// swapping routes — so a single sequence spanning both widgets works
  /// with no extra plumbing.
  List<GlobalKey> get orderedSteps => [
        menu,
        avatar,
        notifications,
        search,
        matchesTab,
        inboxTab,
        chatTab,
        premiumTab,
      ];
}

final appTourKeysProvider = Provider<AppShellTourKeys>((ref) {
  return AppShellTourKeys();
});
