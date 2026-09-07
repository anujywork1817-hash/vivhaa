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

/// App-wide system-back interception: no matter how deep the current
/// screen was pushed (onboarding step, chat window, profile detail,
/// settings, …), the first back press always collapses the stack straight
/// back to the bottom-nav Home tab in one step, rather than popping one
/// screen at a time. Only once the user is already sitting on the Home
/// tab does back raise an "Are you sure you want to exit?" confirmation
/// dialog — one press alone, from anywhere, must never exit outright.
///
/// This has flip-flopped a few times in this repo's history (most
/// recently a one-screen-at-a-time version, then a double-press-within-
/// a-window snackbar). An explicit confirmation dialog is the latest
/// instruction — if you're about to change it again, confirm with
/// whoever's asking first.
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
  bool _exitDialogShowing = false;

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
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _handleBack() {
    final location =
        widget.router.routerDelegate.currentConfiguration.uri.toString();
    final onHomeRoute = location == AppRoutes.home;
    final onHomeTab = ref.read(appShellTabProvider) == AppTab.home;

    // Not on the Home tab of the bottom nav yet (either a pushed screen
    // on top of the shell, or a different tab selected) — one press
    // always collapses straight there, never exits (or prompts to exit)
    // on this press.
    if (!onHomeRoute || !onHomeTab) {
      if (!onHomeTab) {
        ref.read(appShellTabProvider.notifier).state = AppTab.home;
      }
      if (!onHomeRoute) {
        widget.router.go(AppRoutes.home);
      }
      return;
    }

    _confirmExit();
  }

  /// A real confirmation dialog rather than the earlier "press back again"
  /// snackbar — asks once, explicitly, rather than relying on a second
  /// press landing inside a timing window.
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

  @override
  Widget build(BuildContext context) {
    // Always intercepted (never canPop: true) — every case, including the
    // final exit, is decided inside _handleBack rather than delegated to
    // the system's own pop/close behavior.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: widget.child,
    );
  }
}
