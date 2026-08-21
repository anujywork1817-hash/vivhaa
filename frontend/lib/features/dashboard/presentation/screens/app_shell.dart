import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/notifications/push_notification_service.dart';
import '../../../calls/presentation/controllers/call_controller.dart';
import '../../../calls/presentation/screens/incoming_call_screen.dart';
import '../../../chat/data/chat_socket_service.dart';
import '../../../chat/presentation/controllers/chat_controller.dart';
import '../../../chat/presentation/screens/chat_tab_screen.dart';
import '../../../interests/presentation/controllers/interests_controller.dart';
import '../../../premium/presentation/screens/premium_paywall_screen.dart';
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
  static const _tabs = [
    HomeDashboardScreen(),
    MatchesTabScreen(),
    InboxTabScreen(),
    ChatTabScreen(),
    PremiumPaywallScreen(showSkip: false),
  ];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The socket can die silently while backgrounded (screen lock, Doze,
    // network switch) without the app ever finding out — force a fresh
    // connection on every resume rather than trusting a possibly-zombie
    // one. See ChatSocketService.forceReconnect for the full story.
    if (state == AppLifecycleState.resumed) {
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

    return Scaffold(
      body: IndexedStack(index: activeTab.index, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: activeTab.index,
        onTap: (i) => ref.read(appShellTabProvider.notifier).state = AppTab.values[i],
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(
            icon: const Icon(Icons.people_alt_rounded),
            label: 'Matches',
          ),
          BottomNavigationBarItem(
            icon: _BadgedIcon(icon: Icons.mail_rounded, count: pendingInterests),
            label: 'Inbox',
          ),
          BottomNavigationBarItem(
            icon: _BadgedIcon(icon: Icons.chat_bubble_rounded, count: unreadChats),
            label: 'Chat',
          ),
          const BottomNavigationBarItem(
              icon: Icon(Icons.workspace_premium_rounded), label: 'Premium'),
        ],
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
