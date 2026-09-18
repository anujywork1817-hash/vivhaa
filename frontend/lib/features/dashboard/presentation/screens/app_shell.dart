import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../../../core/notifications/push_notification_service.dart';
import '../../../../core/tour/app_tour_controller.dart';
import '../../../calls/presentation/controllers/call_controller.dart';
import '../../../calls/presentation/screens/incoming_call_screen.dart';
import '../../../chat/data/chat_socket_service.dart';
import '../../../chat/presentation/controllers/chat_controller.dart';
import '../../../chat/presentation/screens/chat_tab_screen.dart';
import '../../../interests/presentation/controllers/interests_controller.dart';
import '../../../premium/presentation/screens/premium_paywall_screen.dart';
import '../../../../shared/models/my_subscription.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../controllers/app_shell_controller.dart';
import 'home_dashboard_screen.dart';
import 'inbox_tab_screen.dart';
import 'matches_tab_screen.dart';

/// Post-onboarding shell: Home / Matches / Inbox / Chat / Premium.
/// Account & settings live behind Home's hamburger menu instead of a
/// bottom-nav tab, matching the reference.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  bool _exitDialogShowing = false;

  static const _tabs = [
    HomeDashboardScreen(),
    MatchesTabScreen(),
    InboxTabScreen(),
    ChatTabScreen(),
    kPremiumFeatureEnabled ? const PremiumPaywallScreen(showSkip: false) : const _PremiumComingSoonScreen(),
  ];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The socket can die silently while backgrounded (screen lock, Doze,
    // network switch) without the app ever finding out — force a fresh
    // connection on every resume rather than trusting a possibly-zombie
    // one. See ChatSocketService.forceReconnect for the full story.
    //
    // BUG: the OS camera/mic permission dialog is a system overlay that
    // fires this exact paused -> resumed cycle even though the app never
    // really left the foreground — every "Allow microphone/camera access?"
    // prompt during startCall()/acceptCall() used to trigger a
    // forceReconnect() right in the middle of call signaling. Closing and
    // reopening the socket there drops whatever call:initiate/call:accept/
    // ICE-candidate send was in flight (ChatSocketService.send is
    // fire-and-forget and silently no-ops while _channel is briefly null
    // mid-reconnect), which is exactly what made a call "cut on one end"
    // the moment the permission prompt appeared. Skipping the reconnect
    // while a call is active avoids tearing down the signaling channel a
    // call setup is actively relying on; a genuinely stale/zombie socket
    // from a real backgrounding will still be caught on the next resume
    // that isn't mid-call.
    if (state == AppLifecycleState.resumed &&
        !ref.read(callControllerProvider.notifier).isCallSetupInProgress) {
      ref.read(chatSocketServiceProvider).forceReconnect();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // initialise() is normally triggered by a fresh login/OTP-verify
    // (see AuthController) and is a no-op if that already happened this
    // process — but a user reopening a killed app while already signed
    // in reaches AppShell via session restore, never through that login
    // code path, so without this the notifications plugin would never
    // actually get set up on exactly the app launch this fix cares about.
    ref.read(pushNotificationServiceProvider).initialise();

    // Asking for camera/mic the moment a user first reaches the main app
    // (rather than lazily at the first real call) means that by the time
    // they actually place or receive one, the OS permission dialog has
    // already been answered — no dialog popping up mid-call-setup to
    // trigger the pause/resume cycle above. Best-effort and silent: a
    // decline here isn't treated as anything but "ask again at call
    // time," which CallController._ensurePermissions still does.
    unawaited(_primeCallPermissions());
  }

  Future<void> _primeCallPermissions() async {
    await [Permission.camera, Permission.microphone].request();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Session-wide, so an interest accepted while the user is on any tab
    // unlocks the chat there and then rather than on the next manual refresh.
    ref.watch(matchLiveUpdatesProvider);

    final activeTab = ref.watch(appShellTabProvider);
    final pendingInterests = ref.watch(pendingReceivedCountProvider);
    final unreadChats = ref.watch(unreadConversationCountProvider);
    final tourKeys = ref.watch(appTourKeysProvider);

    // An incoming call can arrive while the user is anywhere in the main
    // app (not just inside a specific chat), so it's surfaced here rather
    // than from any one screen — pushed on the root navigator so it
    // overlays the bottom nav and whatever tab is currently showing.
    ref.listen(callControllerProvider, (previous, next) {
      if (next.status == CallStatus.ringing && previous?.status != CallStatus.ringing) {
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const IncomingCallScreen()),
        );
      }
    });

    // This IS the routed widget for '/home' — the only GoRoute this app
    // registers for the bottom-nav shell, with the five tabs (Home/
    // Matches/Inbox/Chat/Premium) switched purely via IndexedStack, never
    // a route change. That makes AppShell's build the one place with a
    // real ModalRoute ancestor for PopScope to attach to while sitting on
    // any of those tabs — a PopScope placed further up, outside the
    // Router/Navigator (as this used to be, in app.dart), silently finds
    // no ModalRoute and never intercepts anything, so back closes the app
    // immediately no matter which tab is showing.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
      body: IndexedStack(index: activeTab.index, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: activeTab.index,
        onTap: (i) => ref.read(appShellTabProvider.notifier).state = AppTab.values[i],
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(
            icon: Showcase(
              key: tourKeys.matchesTab,
              title: 'Matches',
              description: 'Browse profiles picked for you.',
              child: const Icon(Icons.people_alt_rounded),
            ),
            label: 'Matches',
          ),
          BottomNavigationBarItem(
            icon: Showcase(
              key: tourKeys.inboxTab,
              title: 'Inbox',
              description: 'See who\'s interested in you and respond.',
              child: _BadgedIcon(icon: Icons.mail_rounded, count: pendingInterests),
            ),
            label: 'Inbox',
          ),
          BottomNavigationBarItem(
            icon: Showcase(
              key: tourKeys.chatTab,
              title: 'Chat',
              description: 'Message your matches directly.',
              child: _BadgedIcon(icon: Icons.chat_bubble_rounded, count: unreadChats),
            ),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Showcase(
              key: tourKeys.premiumTab,
              title: 'Premium',
              description: 'Unlock premium membership perks here.',
              child: const Icon(Icons.workspace_premium_rounded),
            ),
            label: 'Premium',
          ),
        ],
      ),
      ),
    );
  }

  /// One press always collapses straight to the Home tab if the user
  /// isn't already there; only once already on Home does back raise an
  /// "Are you sure you want to exit?" confirmation — one press alone must
  /// never exit outright.
  void _handleBack() {
    final onHomeTab = ref.read(appShellTabProvider) == AppTab.home;
    if (!onHomeTab) {
      ref.read(appShellTabProvider.notifier).state = AppTab.home;
      return;
    }
    _confirmExit();
  }

  Future<void> _confirmExit() async {
    // A rapid double back-press can fire this twice before the first
    // dialog even paints; the guard flag (not just checking Navigator's
    // route stack, which a dialog barrier itself changes) keeps the
    // second press a no-op instead of stacking two dialogs.
    if (_exitDialogShowing) return;
    _exitDialogShowing = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Exit Vivah?'),
        content: const Text('Are you sure you want to exit the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );

    _exitDialogShowing = false;
    if (confirmed == true) SystemNavigator.pop();
  }
}

/// Shown in place of the real paywall/plan screens while premium is
/// disabled app-wide (see [kPremiumFeatureEnabled]) — the nav tab stays
/// visible, but tapping it no longer drops the user into a paywall flow
/// for a feature that isn't actually available yet.
class _PremiumComingSoonScreen extends StatelessWidget {
  const _PremiumComingSoonScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: const EmptyState(
        icon: Icons.workspace_premium_rounded,
        title: 'Premium — Coming Soon',
        message: "We're putting the finishing touches on premium membership. Check back soon!",
      ),
    );
  }
}

class _BadgedIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  const _BadgedIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return Icon(icon);
    return Badge(
      label: Text('$count'),
      child: Icon(icon),
    );
  }
}
