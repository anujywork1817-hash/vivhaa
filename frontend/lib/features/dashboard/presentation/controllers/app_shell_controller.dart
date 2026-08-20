import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index of the active bottom-nav tab in [AppShell]. Lives outside the
/// shell's own State so any screen nested inside a tab (e.g. Home's
/// search icon) can switch tabs without a callback threaded down through
/// IndexedStack.
enum AppTab { home, matches, inbox, chat, premium }

final appShellTabProvider = StateProvider<AppTab>((ref) => AppTab.home);
