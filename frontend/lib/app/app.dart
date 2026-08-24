import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:showcaseview/showcaseview.dart';
import '../core/router/app_router.dart';
import '../core/router/app_routes.dart';
import '../core/theme/app_scroll_behavior.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_preferences_controller.dart';
import '../core/tour/app_tour_controller.dart';
import '../features/dashboard/presentation/controllers/app_shell_controller.dart';

class ShaadiApp extends ConsumerWidget {
  const ShaadiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final preferences = ref.watch(themePreferencesProvider);
    return MaterialApp.router(
      title: 'Vivah',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: preferences.themeMode,
      scrollBehavior: const AppScrollBehavior(),
      // A single MediaQuery override at the app root scales every Text
      // widget's rendered size without needing to thread a font-scale
      // value through AppTypography's individual TextStyles.
      // ShowCaseWidget must sit above the Navigator so any Showcase
      // wrapped around a widget deep inside a route can find it via
      // ShowCaseWidget.of(context) — placing it here, inside
      // MaterialApp.router's builder, puts it above every route while
      // still living inside MaterialApp itself (Theme/Localizations
      // stay reachable from the ShowCaseWidget's own builder callback).
      //
      // _BackButtonGate MUST wrap `child` here, not MaterialApp.router
      // from outside (as it used to) — PopScope only actually registers
      // itself against the nearest ModalRoute ancestor, and there is no
      // ModalRoute at all above the Router/Navigator MaterialApp.router
      // creates. A PopScope placed outside it silently finds nothing to
      // attach to, so every one of its checks (collapse to Home, the
      // double-back-to-exit window) never ran — every back press fell
      // straight through to Android's default "pop the Activity", i.e.
      // the app just closed on the very first press from anywhere.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(preferences.fontSize.scale),
        ),
        child: ShowCaseWidget(
          // Only fires on a natural "reached the last step" completion —
          // Skip calls ShowCaseWidgetState.dismiss() directly, which
          // bypasses this, so the Skip button clears tourActiveProvider
          // itself (see home_dashboard_screen.dart).
          onFinish: () => ref.read(tourActiveProvider.notifier).state = false,
          builder: (context) => _BackButtonGate(router: router, child: child!),
        ),
      ),
      routerConfig: router,
    );
  }
}

/// App-wide system-back interception: a back press steps back one screen
/// at a time exactly like normal (onboarding step, chat window, profile
/// detail, settings, … all pop one level per press) until there's nowhere
/// left to pop to — the bottom-nav shell sitting on any tab but Home, or
/// the Home tab itself. From a non-Home tab, back switches to the Home tab
/// rather than exiting outright. Only once actually on the Home tab does
/// back arm a "press again to exit" window; a second press inside that
/// window exits the app, and letting the window lapse resets it.
///
/// This has flip-flopped with a collapse-to-Dashboard version a few times
/// in this repo's history. Per an explicit, detailed spec (with acceptance
/// tests) received directly, one-screen-at-a-time is the intended final
/// behavior — if you're about to change it again, treat that spec as
/// authoritative over any earlier comment claiming otherwise.
///
/// go_router 14.x runs every declared [GoRoute] on a single root
/// [Navigator] (nested navigators only appear with ShellRoute/
/// StatefulShellRoute, which this app doesn't use), so a single
/// [PopScope] wrapping the whole [MaterialApp.router] is enough to catch
/// every system back press app-wide without touching in-screen back
/// arrows, which call `context.pop()`/`Navigator.pop()` directly and
/// never invoke this pop route at all.
class _BackButtonGate extends ConsumerStatefulWidget {
  const _BackButtonGate({required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<_BackButtonGate> createState() => _BackButtonGateState();
}

class _BackButtonGateState extends ConsumerState<_BackButtonGate> {
  static const _exitWindow = Duration(seconds: 2);
  DateTime? _lastBackPressAt;
  Timer? _exitWindowTimer;

  // Handles an incoming shared-profile App Link (see
  // core/config/deep_link_config.dart — not reachable from outside the
  // app until a real domain/Play Store listing exist, but the app is
  // ready to act on one the moment the OS delivers it, cold-start or
  // while already running). Lives here rather than a separate widget
  // since this is already the one root-level StatefulWidget wrapping the
  // whole router.
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleIncomingLink);
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleIncomingLink(uri);
    });
  }

  void _handleIncomingLink(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length == 2 && segments[0] == 'p' && segments[1].isNotEmpty) {
      widget.router.go(AppRoutes.sharedProfileLinkPath(segments[1]));
    }
  }

  @override
  void dispose() {
    _exitWindowTimer?.cancel();
    _linkSubscription?.cancel();
    super.dispose();
  }

  /// Only ever called when [canPop] was false, i.e. the shell is sitting on
  /// AppRoutes.home with nowhere left in the route stack to pop to — so
  /// this only ever needs to handle "switch off a non-Home tab" or the
  /// exit-confirmation window, never a normal screen-to-screen back.
  void _handleRootBack() {
    if (ref.read(appShellTabProvider) != AppTab.home) {
      ref.read(appShellTabProvider.notifier).state = AppTab.home;
      return;
    }

    final now = DateTime.now();
    if (_lastBackPressAt != null &&
        now.difference(_lastBackPressAt!) <= _exitWindow) {
      _exitWindowTimer?.cancel();
      SystemNavigator.pop();
      return;
    }

    _lastBackPressAt = now;
    _exitWindowTimer?.cancel();
    _exitWindowTimer = Timer(_exitWindow, () => _lastBackPressAt = null);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final location =
        widget.router.routerDelegate.currentConfiguration.uri.toString();
    // Nothing left to pop to once we're back at the shell's base route —
    // switching bottom-nav tabs never changes this location (the tabs
    // live inside one route via appShellTabProvider, not real navigation
    // stack entries), so canPop must key off location alone: gating it on
    // "and already on the Home tab" too would leave canPop wrongly true
    // while sitting on e.g. Matches with nothing actually left to pop,
    // letting the system fall through to its own default (closing the
    // app) instead of reaching _handleRootBack to switch to Home first.
    final atRoot = location == AppRoutes.home;

    return PopScope(
      canPop: !atRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleRootBack();
      },
      child: widget.child,
    );
  }
}
