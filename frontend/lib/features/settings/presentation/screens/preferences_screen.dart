import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_preferences_controller.dart';

/// App-wide display preferences — theme (light/dark/system) and font size.
/// Both persist across restarts via [themePreferencesProvider] and take
/// effect immediately app-wide (see app.dart), not just on this screen.
class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(themePreferencesProvider);
    final controller = ref.read(themePreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Preferences')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Theme', style: context.textStyles.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Choose how Vivah looks. "System default" follows your phone\'s '
            'own light/dark setting automatically.',
            style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          _OptionCard(
            children: [
              _ThemeModeOption(
                icon: Icons.brightness_auto_rounded,
                label: 'System default',
                selected: prefs.themeMode == ThemeMode.system,
                onTap: () => controller.setThemeMode(ThemeMode.system),
              ),
              _ThemeModeOption(
                icon: Icons.light_mode_rounded,
                label: 'Light',
                selected: prefs.themeMode == ThemeMode.light,
                onTap: () => controller.setThemeMode(ThemeMode.light),
              ),
              _ThemeModeOption(
                icon: Icons.dark_mode_rounded,
                label: 'Dark',
                selected: prefs.themeMode == ThemeMode.dark,
                onTap: () => controller.setThemeMode(ThemeMode.dark),
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Font size', style: context.textStyles.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Adjust how large text appears throughout the app.',
            style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          _OptionCard(
            children: [
              for (final size in AppFontSize.values)
                _FontSizeOption(
                  size: size,
                  selected: prefs.fontSize == size,
                  onTap: () => controller.setFontSize(size),
                  showDivider: size != AppFontSize.values.last,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final List<Widget> children;
  const _OptionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _ThemeModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showDivider;

  const _ThemeModeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: context.colors.muted),
          title: Text(label),
          trailing: selected
              ? Icon(Icons.check_circle_rounded, color: context.colors.accent)
              : const Icon(Icons.circle_outlined, color: Colors.transparent),
          onTap: onTap,
        ),
        if (showDivider) Divider(height: 1, color: context.colors.line),
      ],
    );
  }
}

class _FontSizeOption extends StatelessWidget {
  final AppFontSize size;
  final bool selected;
  final VoidCallback onTap;
  final bool showDivider;

  const _FontSizeOption({
    required this.size,
    required this.selected,
    required this.onTap,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: Text('Aa',
              style: TextStyle(fontSize: 16 * size.scale, fontWeight: FontWeight.w600)),
          title: Text(size.label),
          trailing: selected
              ? Icon(Icons.check_circle_rounded, color: context.colors.accent)
              : const Icon(Icons.circle_outlined, color: Colors.transparent),
          onTap: onTap,
        ),
        if (showDivider) Divider(height: 1, color: context.colors.line),
      ],
    );
  }
}
