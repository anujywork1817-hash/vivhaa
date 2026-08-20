import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_scroll_behavior.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_preferences_controller.dart';

class ShaadiApp extends ConsumerWidget {
  const ShaadiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final preferences = ref.watch(themePreferencesProvider);
    return MaterialApp.router(
      title: 'Vivaha',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: preferences.themeMode,
      scrollBehavior: const AppScrollBehavior(),
      // A single MediaQuery override at the app root scales every Text
      // widget's rendered size without needing to thread a font-scale
      // value through AppTypography's individual TextStyles.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(preferences.fontSize.scale),
        ),
        child: child!,
      ),
      routerConfig: router,
    );
  }
}
