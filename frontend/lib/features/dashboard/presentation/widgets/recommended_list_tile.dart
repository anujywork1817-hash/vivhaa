import 'package:flutter/material.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';

/// Horizontal row tile used in the "Recommended for you" list.
class RecommendedListTile extends StatelessWidget {
  final MatchProfile profile;
  final VoidCallback? onTap;

  const RecommendedListTile({super.key, required this.profile, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: context.colors.line),
        ),
        child: Row(
          children: [
            ProfileAvatar(name: profile.name, size: 52, borderRadius: BorderRadius.circular(12)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text('${profile.name}, ${profile.age}',
                            style: context.textStyles.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (profile.verified) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified_rounded, size: 15, color: context.colors.accent),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${profile.profession} · ${profile.city}',
                    style: context.textStyles.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${profile.education} · ${profile.heightLabel}',
                    style: context.textStyles.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}
