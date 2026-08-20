import 'package:flutter/material.dart';

/// Maps a paid plan's duration to a metal tier name/color — Platinum for
/// monthly, Silver for quarterly, Gold for yearly (the longest, best-value
/// commitment). Shared by the plan picker and the membership screen so
/// both always agree on which duration is which tier and color.
class PlanTier {
  final String label;
  final Color accent;
  final Color tint;

  const PlanTier._(this.label, this.accent, this.tint);

  static const platinum = PlanTier._('Platinum', Color(0xFF5C7A93), Color(0xFFE7EEF2));
  static const silver = PlanTier._('Silver', Color(0xFF8C8C8C), Color(0xFFEEEEEE));
  static const gold = PlanTier._('Gold', Color(0xFFC79B1F), Color(0xFFFBF1D6));

  /// [durationDays] rounds tolerate a plan being defined as e.g. 29 or 31
  /// days instead of an exact 30 — buckets by nearest calendar unit rather
  /// than requiring an exact day count.
  factory PlanTier.forDuration(int durationDays) {
    if (durationDays >= 300) return gold; // yearly
    if (durationDays >= 80) return silver; // quarterly
    return platinum; // monthly
  }
}
