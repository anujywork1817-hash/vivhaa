import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';

/// Circular avatar + first-name tile used in the "New Members" horizontal
/// row.
class MemberAvatarTile extends StatelessWidget {
  final MatchProfile profile;
  final VoidCallback? onTap;

  const MemberAvatarTile({super.key, required this.profile, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(40),
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Stack(
              children: [
                ProfileAvatar(name: profile.name, size: 64),
                if (profile.isNew)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: context.colors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.colors.bg, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              profile.name.split(' ').first,
              style: context.textStyles.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
