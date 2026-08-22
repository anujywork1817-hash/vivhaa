import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the new-user coach-mark walkthrough (see
/// AppShellTourKeys below) has already auto-played once, so it never
/// interrupts the Dashboard again after the first successful run — mirrors
/// [AppRatingController]'s use of a single SharedPreferences flag, but
/// exposes one-shot read/write methods instead of a reactive [StateNotifier]
/// since the Dashboard only ever needs the answer once, at its first frame,
/// and awaiting a provider's async load would risk a race between "has the
/// flag loaded yet" and "have we already rendered the first frame".
class AppTourController {
  static const _hasSeenTourKey = 'has_seen_app_tour';

  Future<bool> hasSeenTour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasSeenTourKey) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenTourKey, true);
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
