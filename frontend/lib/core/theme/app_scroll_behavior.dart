import 'package:flutter/material.dart';

/// App-wide scroll feel: bouncy (iOS-style) physics on every platform
/// instead of Android's default hard-clamped stop, with the blue overscroll
/// glow removed since bouncing physics makes it redundant. Applied once via
/// [MaterialApp.scrollBehavior] so every ListView/GridView/PageView/
/// SingleChildScrollView in the app gets it automatically, rather than
/// having to set physics on each one individually.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}
