import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:showcaseview/showcaseview.dart';
import '../core/router/app_router.dart';
import '../core/router/app_routes.dart';
import '../core/theme/app_scroll_behavior.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_preferences_controller.dart';
import '../core/tour/app_tour_controller.dart';

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
      // _DeepLinkListener only handles incoming App Links here — the
      // system-back interception used to live in this same wrapper via a
      // PopScope, but MaterialApp.router's `builder` sits *above* the
      // Router/Navigator entirely, so there is no ModalRoute anywhere
      // above it for PopScope to register against. A PopScope placed here
      // silently finds nothing to attach to, so it never actually
      // intercepted anything — every back press fell straight through to
      // Android's default "pop the Activity" on the very first press,
      // from any tab, including Home. The real back-button gate now lives
      // in AppShell.build (see AppShell's PopScope) — that widget is the
      // actual routed page, with a real ModalRoute ancestor.
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
          builder: (context) => _DeepLinkListener(router: router, child: child!),
        ),
      ),
      routerConfig: router,
    );
  }
}

/// Handles an incoming shared-profile App Link (see
/// core/config/deep_link_config.dart — not reachable from outside the app
/// until a real domain/Play Store listing exist, but the app is ready to
/// act on one the moment the OS delivers it, cold-start or while already
/// running).
///
/// This used to also carry the app-wide system-back interception via a
/// PopScope, but MaterialApp.router's `builder` sits *above* the
/// Router/Navigator entirely — there is no ModalRoute anywhere above it,
/// so a PopScope placed here silently finds nothing to register against
/// and never actually intercepts anything (every back press falls
/// straight through to Android's default "pop the Activity"). The
/// back-button gate now lives in AppShell.build instead — that widget IS
/// the routed page for '/home', so it has a real ModalRoute ancestor.
class _DeepLinkListener extends ConsumerStatefulWidget {
  const _DeepLinkListener({required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<_DeepLinkListener> createState() => _DeepLinkListenerState();
}

class _DeepLinkListenerState extends ConsumerState<_DeepLinkListener> {
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

  @override
  Widget build(BuildContext context) => widget.child;
}
