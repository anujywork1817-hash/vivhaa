import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/feedback/error_state.dart';
import '../../../../shared/widgets/feedback/shimmer_box.dart';
import '../../../../shared/widgets/misc/locked_profile_photo.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../../../calls/presentation/controllers/call_controller.dart';
import '../../../calls/presentation/screens/active_call_screen.dart';
import '../../../chat/presentation/controllers/chat_controller.dart';
import '../../../dashboard/presentation/controllers/app_shell_controller.dart';
import '../../../interests/presentation/controllers/interests_controller.dart';
import '../controllers/profile_detail_controller.dart';
import '../widgets/profile_actions_sheet.dart';
import '../widgets/similar_profiles_section.dart';
import '../widgets/verification_info_sheet.dart';
import 'photo_gallery_screen.dart';

class ProfileDetailScreen extends ConsumerWidget {
  final String profileId;
  const ProfileDetailScreen({super.key, required this.profileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileDetailProvider(profileId));

    return Scaffold(
      body: async.when(
        loading: () => const _DetailShimmer(),
        error: (e, st) {
          final failure = _asFailure(e);
          // The backend returns 403/forbidden specifically (and only) when
          // this profile is private and we're not its owner — everything
          // else (network, 404, 500) is a real error and keeps the normal
          // retry UI. A private profile isn't an error to recover from, so
          // it gets its own blurred/no-details view instead of a generic
          // "something went wrong" state.
          if (failure.type == AppFailureType.forbidden) {
            return _PrivateProfileView(onBack: () => Navigator.of(context).pop());
          }
          // A 404 here almost always means a block, in either direction —
          // GetByID/GetByCode treat a blocked profile as not-found rather
          // than forbidden, so a block relationship never leaks to the
          // blocked party. A stale link/notification pointing at a
          // genuinely deleted profile lands here too; either way, retrying
          // won't help, so this skips the generic retry UI.
          if (failure.type == AppFailureType.notFound) {
            return _UnavailableProfileView(onBack: () => Navigator.of(context).pop());
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    alignment: Alignment.centerLeft,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  ErrorStateView(
                    failure: failure,
                    onRetry: () => ref.invalidate(profileDetailProvider(profileId)),
                  ),
                ],
              ),
            ),
          );
        },
        data: (detail) => _ProfileDetailBody(detail: detail),
      ),
    );
  }
}

/// Shown in place of the profile when it's private and we're not its
/// owner: a blurred silhouette and no details at all — matching what a
/// private profile is supposed to guarantee (nothing about them is
/// visible to a member they haven't connected with), rather than a
/// generic error screen.
class _PrivateProfileView extends StatelessWidget {
  final VoidCallback onBack;
  const _PrivateProfileView({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(80),
                    child: SizedBox(
                      width: 160,
                      height: 160,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: TileMode.decal),
                        child: const ProfileAvatar(name: '?', size: 160),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Icon(Icons.lock_outline_rounded, color: context.colors.muted, size: 20),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'This user has set their profile to private',
                    style: context.textStyles.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    "Their photo and details aren't visible until they make their profile public.",
                    style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown for a 404 on profile detail — almost always a block relationship
/// (in either direction), occasionally a stale link to a deleted profile.
/// Deliberately vague ("no longer available") rather than naming a block,
/// so this can't be used to confirm a block exists.
class _UnavailableProfileView extends StatelessWidget {
  final VoidCallback onBack;
  const _UnavailableProfileView({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_off_rounded, color: context.colors.muted, size: 40),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'This profile is no longer available',
                    style: context.textStyles.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    "It may have been removed, or you may no longer be able to view it.",
                    style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDetailBody extends ConsumerWidget {
  final dynamic detail; // ProfileDetail — typed loosely to keep imports tight here
  const _ProfileDetailBody({required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = detail.summary as MatchProfile;
    final isInterested = ref.watch(isInterestSentProvider(summary.id));

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _PhotoHeader(detail: detail),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('${summary.name}, ${summary.age}',
                              style: context.textStyles.headlineMedium),
                        ),
                        InkWell(
                          onTap: () => showModalBottomSheet(
                            context: context,
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                            builder: (_) => VerificationInfoSheet(detail: detail),
                          ),
                          child: Icon(
                            summary.verified ? Icons.verified_rounded : Icons.verified_outlined,
                            color: summary.verified ? context.colors.accent : context.colors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${summary.profession} · ${summary.city}',
                        style: context.textStyles.bodyMedium
                            ?.copyWith(color: context.colors.muted)),
                    const SizedBox(height: 2),
                    Text('Profile ID: ${summary.profileCode}',
                        style: context.textStyles.bodySmall),
                    const SizedBox(height: AppSpacing.lg),
                    _DetailSection(title: 'About', rows: const {}, freeText: detail.about),
                    _DetailSection(title: 'Family', rows: {
                      "Father's occupation": detail.fatherOccupation,
                      "Mother's occupation": detail.motherOccupation,
                      'Siblings': '${detail.brothers} brother(s), ${detail.sisters} sister(s)',
                      'Family type': detail.familyType,
                      'Family values': detail.familyValues,
                    }),
                    _DetailSection(title: 'Career & Education', rows: {
                      'Education': summary.education,
                      'Profession': summary.profession,
                      'Annual income': summary.incomeBracket,
                    }),
                    _DetailSection(title: 'Astro & Physical', rows: {
                      'Height': summary.heightLabel,
                      'Manglik': summary.manglik,
                      'Rashi': detail.rashi,
                      'Nakshatra': detail.nakshatra,
                    }),
                    _DetailSection(title: 'Lifestyle', rows: {
                      'Diet': summary.diet,
                      'Smoking': detail.smoking,
                      'Drinking': detail.drinking,
                    }),
                    _DetailSection(title: 'Partner Preference', rows: {
                      'Looking for': detail.partnerPreferenceSummary,
                    }),
                  ],
                ),
              ),
              SimilarProfilesSection(profileId: summary.id),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
        _ActionBar(
          profile: summary,
          isInterested: isInterested,
        ),
      ],
    );
  }
}

class _PhotoHeader extends ConsumerWidget {
  final dynamic detail;
  const _PhotoHeader({required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoIds = detail.photoIds as List<String>;
    final summary = detail.summary as MatchProfile;
    final name = summary.name;
    final isConnected = ref.watch(conversationForProfileProvider(summary.id)) != null;
    final showLocked = summary.photoLocked && !isConnected;

    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: showLocked
              ? GestureDetector(
                  // No gallery to open while photos are hidden, but the
                  // tap target stays so the area still feels part of the
                  // card rather than inert.
                  onTap: () {},
                  child: LockedProfilePhoto(name: name),
                )
              // A horizontal PageView, not a custom drag handler: the
              // gesture arena resolves by axis, so horizontal swipes page
              // through photos while vertical drags fall through to the
              // ListView that owns the page. Rolling our own pan handler
              // here is what creates the classic "can't scroll over the
              // image" conflict.
              : _PhotoCarousel(
                  photoUrls: photoIds,
                  name: name,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PhotoGalleryScreen(
                      args: PhotoGalleryArgs(photoIds: photoIds, name: name),
                    ),
                  )),
                ),
        ),
        Positioned(
          left: 4,
          top: 4,
          child: SafeArea(
            child: IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black38,
                child: Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        if (!showLocked && photoIds.length > 1)
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_library_outlined, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text('${photoIds.length} photos',
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Swipeable photo carousel for the profile header.
///
/// Uses a plain horizontal [PageView] deliberately. Because it only claims
/// horizontal drags, Flutter's gesture arena hands vertical drags to the
/// enclosing ListView — so the page still scrolls when the finger starts
/// on the photo. A hand-written pan/drag handler would claim both axes and
/// swallow the scroll, which is the usual cause of this bug.
class _PhotoCarousel extends StatefulWidget {
  final List<String> photoUrls;
  final String name;
  final VoidCallback onTap;

  const _PhotoCarousel({
    required this.photoUrls,
    required this.name,
    required this.onTap,
  });

  @override
  State<_PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<_PhotoCarousel> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No photos yet — the initials placeholder still needs to be tappable
    // and must not block the page's vertical scroll.
    if (widget.photoUrls.isEmpty) {
      return GestureDetector(
        onTap: widget.onTap,
        child: ProfileAvatar(
            name: widget.name, size: double.infinity, borderRadius: BorderRadius.zero),
      );
    }

    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.photoUrls.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => GestureDetector(
            onTap: widget.onTap,
            child: ProfileAvatar(
              name: widget.name,
              size: double.infinity,
              borderRadius: BorderRadius.zero,
              photoUrl: widget.photoUrls[i],
            ),
          ),
        ),
        if (widget.photoUrls.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.photoUrls.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.white54,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final Map<String, String> rows;
  final String? freeText;
  const _DetailSection({required this.title, required this.rows, this.freeText});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: context.colors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: context.textStyles.titleSmall?.copyWith(color: context.colors.accent)),
            const SizedBox(height: 8),
            if (freeText != null)
              Text(freeText!, style: context.textStyles.bodyMedium),
            ...rows.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 140, child: Text(e.key, style: context.textStyles.bodySmall)),
                      Expanded(
                          child: Text(e.value,
                              style: context.textStyles.bodyMedium, textAlign: TextAlign.right)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}


class _ActionBar extends ConsumerWidget {
  final MatchProfile profile;
  final bool isInterested;

  const _ActionBar({
    required this.profile,
    required this.isInterested,
  });

  String get profileId => profile.id;
  String get name => profile.name;

  /// Jumps back to the shell's Inbox tab (Sent/Received interests) — the
  /// only place interests are browsable, so the snackbars above always
  /// offer a direct path there instead of leaving the user to hunt for it.
  void _goToInbox(BuildContext context, WidgetRef ref) {
    ref.read(appShellTabProvider.notifier).state = AppTab.inbox;
    context.go(AppRoutes.home);
  }

  /// Lets someone change their mind on an already-sent interest — confirm,
  /// withdraw, and offer an UNDO that just re-sends it, so a mis-tap or a
  /// change of heart isn't a one-way door.
  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final record = ref.read(sentInterestForProfileProvider(profileId));
    if (record == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Withdraw interest?'),
        content: Text('Your interest sent to $name will be withdrawn.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Withdraw', style: TextStyle(color: dialogContext.colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final failure = await ref.read(interestsActionsProvider).withdraw(record.id);
    if (!context.mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Interest withdrawn from $name.'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            final resendFailure = await ref.read(interestsActionsProvider).send(profile);
            if (resendFailure != null && context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(resendFailure.message)));
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = ref.watch(conversationForProfileProvider(profileId));
    // An accepted interest unlocks chat even before the conversation list has
    // caught up, so prefer it and fall back to the existing lookup.
    final chatTarget =
        ref.watch(acceptedPartnerUserIdProvider(profileId)) ?? conversation?.id;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: context.colors.line)),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.chat_bubble_outline_rounded,
                  color: chatTarget != null ? context.colors.accent : context.colors.muted),
              tooltip: chatTarget != null ? 'Chat' : 'Chat unlocks once interest is accepted',
              onPressed: () {
                if (chatTarget != null) {
                  context.push(AppRoutes.chatWindowPath(chatTarget));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Chat opens once you both express interest and it\'s accepted.'),
                      action: SnackBarAction(
                        label: 'MY INTERESTS',
                        onPressed: () => _goToInbox(context, ref),
                      ),
                    ),
                  );
                }
              },
            ),
            // Calling requires the same mutual-connection gate as chat —
            // only shown enabled once a conversation exists.
            if (conversation != null && !conversation.isBlocked) ...[
              IconButton(
                icon: Icon(Icons.call_rounded, color: context.colors.accent),
                tooltip: 'Voice call',
                onPressed: () async {
                  if (ref.read(callControllerProvider).isActive) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text("You're already on a call.")));
                    return;
                  }
                  unawaited(ref.read(callControllerProvider.notifier).startCall(
                        peerUserId: conversation.id,
                        peerName: name,
                        peerPhotoUrl: profile.photoSeed,
                        isVideo: false,
                      ));
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ActiveCallScreen()),
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.videocam_rounded, color: context.colors.accent),
                tooltip: 'Video call',
                onPressed: () async {
                  if (ref.read(callControllerProvider).isActive) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text("You're already on a call.")));
                    return;
                  }
                  unawaited(ref.read(callControllerProvider.notifier).startCall(
                        peerUserId: conversation.id,
                        peerName: name,
                        peerPhotoUrl: profile.photoSeed,
                      ));
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ActiveCallScreen()),
                  );
                },
              ),
            ],
            Expanded(
              child: PrimaryButton(
                label: isInterested ? 'Interest Sent' : 'Express Interest',
                onPressed: isInterested
                    ? () => _withdraw(context, ref)
                    : () async {
                        final failure = await ref.read(interestsActionsProvider).send(profile);
                        if (!context.mounted) return;
                        if (failure != null) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(failure.message)));
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Interest sent to $name.'),
                            action: SnackBarAction(
                              label: 'VIEW',
                              onPressed: () => _goToInbox(context, ref),
                            ),
                          ),
                        );
                      },
                trailingIcon: isInterested ? Icons.check_rounded : Icons.favorite_rounded,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'More',
              onPressed: () => showModalBottomSheet(
                context: context,
                builder: (_) => ProfileActionsSheet(
                  profileId: profileId,
                  name: name,
                  onBlocked: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailShimmer extends StatelessWidget {
  const _DetailShimmer();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBox(width: double.infinity, height: 320, borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
            const SizedBox(height: AppSpacing.lg),
            ShimmerBox(width: 180, height: 22, borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: AppSpacing.md),
            ShimmerBox(width: double.infinity, height: 90, borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          ],
        ),
      ),
    );
  }
}

AppFailure _asFailure(Object e) => e is AppFailure ? e : AppFailure.unknown(e.toString());
