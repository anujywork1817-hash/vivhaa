import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/tour/app_tour_controller.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../../shared/widgets/feedback/shimmer_box.dart';
import '../../../../shared/widgets/misc/locked_profile_photo.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../../../chat/presentation/controllers/chat_controller.dart';
import '../../../interests/presentation/controllers/interests_controller.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';
import '../controllers/app_shell_controller.dart';
import '../controllers/dashboard_controller.dart';

/// "My Shaadi" home tab — profile summary, promo banner, profile
/// completion prompts, Premium Matches / New Matches rails, footer.
class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  ConsumerState<HomeDashboardScreen> createState() =>
      _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen> {
  @override
  void initState() {
    super.initState();
    // AppShell keeps every tab alive via IndexedStack, so this initState
    // only ever runs once per app session (not once per visit to the Home
    // tab) — exactly what's wanted for a "first time only" auto-trigger.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final seen = await ref.read(appTourControllerProvider).hasSeenTour();
      if (!mounted || seen) return;
      _startTour();
      await ref.read(appTourControllerProvider).markSeen();
    });
  }

  void _startTour() {
    final keys = ref.read(appTourKeysProvider);
    ShowCaseWidget.of(context).startShowCase(keys.orderedSteps);
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final tourKeys = ref.watch(appTourKeysProvider);

    // The "Take a Tour" row in the hamburger menu can't reach this
    // widget's GlobalKeys directly, so it flips this flag and navigates
    // back to Home instead — since Home is already mounted (IndexedStack),
    // this listener is what actually replays the walkthrough on demand.
    ref.listen<bool>(tourReplayRequestedProvider, (previous, requested) {
      if (!requested) return;
      ref.read(tourReplayRequestedProvider.notifier).state = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startTour();
      });
    });

    return Scaffold(
      appBar: AppBar(
        leading: Showcase(
          key: tourKeys.menu,
          title: 'Menu',
          description:
              'Open the menu to manage your profile, settings, and more.',
          child: IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => context.push(AppRoutes.menu),
          ),
        ),
        title: const Text('My Vivah'),
        actions: [
          Showcase(
            key: tourKeys.avatar,
            title: 'Your Profile',
            description: 'This is you — tap to view or edit your profile.',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.push(AppRoutes.editProfile),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: ProfileAvatar(
                  name: draft.fullName ?? '',
                  photoUrl: draft.profilePhotoUrl,
                  size: 32,
                ),
              ),
            ),
          ),
          Showcase(
            key: tourKeys.notifications,
            title: 'Notifications',
            description: 'See interests, matches, and messages here.',
            child: Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_none_rounded),
                  onPressed: () => context.push(AppRoutes.notifications),
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: context.colors.accent,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: context.colors.bg, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(todayMatchesProvider);
          ref.invalidate(newMembersProvider);
          ref.invalidate(recommendedMatchesProvider);
          ref.invalidate(notificationsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          children: [
            Showcase(
              key: tourKeys.search,
              title: 'Search',
              description: 'Search for matches by name or profile ID.',
              child: const _SearchBarEntry(),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _CompleteProfileCard(),
            const SizedBox(height: AppSpacing.xl),
            _MatchesRailHeader(
              title: 'Premium Matches',
              count: ref.watch(recommendedMatchesProvider).valueOrNull?.length,
            ),
            const SizedBox(height: AppSpacing.md),
            _MatchesRail(async: ref.watch(recommendedMatchesProvider)),
            const SizedBox(height: AppSpacing.xl),
            _MatchesRailHeader(
              title: 'New Matches',
              count: ref.watch(newMembersProvider).valueOrNull?.length,
            ),
            const SizedBox(height: AppSpacing.md),
            _MatchesRail(async: ref.watch(newMembersProvider)),
            const SizedBox(height: AppSpacing.xxl),
            const _FooterSocialRow(),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// Looks like a search field but isn't one — tapping it opens the real
/// search screen (BasicSearchScreen), same destination the Matches tab's
/// "Search" chip already uses, so Home and Matches agree on where search
/// actually lives instead of each rolling its own.
class _SearchBarEntry extends StatelessWidget {
  const _SearchBarEntry();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Material(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRoutes.basicSearch),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              border: Border.all(color: context.colors.line),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded,
                    size: 20, color: context.colors.muted),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Search by name, city, profession…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: context.colors.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompleteProfileCard extends ConsumerWidget {
  const _CompleteProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(profileCreationControllerProvider).draft;
    // Each prompt carries the destination that actually fixes it — they
    // used to be inert rows (onTap: () {}), so tapping a "complete your
    // profile" nudge did nothing at all. The middle one also described
    // itself as "astro details" while checking the About Me field.
    final missing = <({String label, VoidCallback onTap})>[
      if (draft.profilePhotoUrl == null)
        (
          label: 'Add a profile photo',
          onTap: () => context.push(AppRoutes.managePhotos)
        ),
      if (draft.aboutMe == null || draft.aboutMe!.isEmpty)
        (
          label: 'Write about yourself',
          onTap: () => context.push(AppRoutes.editProfile)
        ),
      if (draft.hobbies.isEmpty)
        (
          label: 'Add hobbies & interests',
          onTap: () => context.push(AppRoutes.hobbies, extra: true)
        ),
    ];
    if (missing.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Complete your Profile', style: context.textStyles.titleMedium),
          const SizedBox(height: 2),
          Text('Completed Profiles get 2x more Connects and responses',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.colors.muted)),
          const SizedBox(height: AppSpacing.md),
          for (final item in missing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: InkWell(
                onTap: item.onTap,
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline_rounded,
                        color: context.colors.accent, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                        child: Text(item.label,
                            style: context.textStyles.bodyMedium)),
                    Icon(Icons.chevron_right_rounded,
                        color: context.colors.muted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MatchesRailHeader extends ConsumerWidget {
  final String title;
  final int? count;
  const _MatchesRailHeader({required this.title, this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text('$title${count != null ? ' ($count)' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.headlineSmall),
          ),
          TextButton(
            // The rails here are a preview of the Matches tab, which is
            // where the full, browsable list already lives.
            onPressed: () =>
                ref.read(appShellTabProvider.notifier).state = AppTab.matches,
            child: const Text('See All'),
          ),
        ],
      ),
    );
  }
}

/// A vertical, full-width stack of match rows — not independently
/// scrollable (no nested ListView/scrollDirection.horizontal): these
/// rows are laid out directly inside HomeDashboardScreen's own vertical
/// ListView, the same as every other section on the page, so there's
/// only ever one scrollable on screen.
class _MatchesRail extends ConsumerWidget {
  final AsyncValue<List<MatchProfile>> async;
  const _MatchesRail({required this.async});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return async.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          children: List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: ShimmerBox(
                  width: double.infinity,
                  height: 110,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
            ),
          ),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Text("Couldn't load matches.",
            style: TextStyle(color: context.colors.muted)),
      ),
      data: (matches) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          children: [
            for (int i = 0; i < matches.length; i++) ...[
              _HomeMatchCard(profile: matches[i]),
              if (i != matches.length - 1)
                const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeMatchCard extends ConsumerWidget {
  final MatchProfile profile;
  const _HomeMatchCard({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isInterested = ref.watch(isInterestSentProvider(profile.id));
    final isConnected =
        ref.watch(conversationForProfileProvider(profile.id)) != null;
    final showLocked = profile.photoLocked && !isConnected;
    // Material wraps InkWell (not the other way round): an opaque
    // Container inside an InkWell paints over the ripple, so tapping the
    // card gave no visual feedback at all and felt unresponsive.
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.profileDetailPath(profile.id)),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: context.colors.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: SizedBox(
                    width: 90,
                    height: 90,
                    child: showLocked
                        ? LockedProfilePhoto(name: profile.name)
                        : ProfileAvatar(
                            name: profile.name,
                            size: 90,
                            borderRadius: BorderRadius.zero,
                            photoUrl: profile.photoSeed),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${profile.name.split(' ').first}, ${profile.age}',
                          style: context.textStyles.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(profile.city,
                          style: context.textStyles.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: isInterested
                              ? null
                              : () async {
                                  final failure = await ref
                                      .read(interestsActionsProvider)
                                      .send(profile);
                                  if (context.mounted && failure != null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            duration:
                                                const Duration(seconds: 3),
                                            content: Text(failure.message)));
                                  }
                                },
                          icon: Icon(
                              isInterested
                                  ? Icons.check_rounded
                                  : Icons.favorite_rounded,
                              size: 13),
                          label: Text(
                              isInterested ? 'Requested' : 'Connect Now',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterSocialRow extends StatelessWidget {
  const _FooterSocialRow();

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.camera_alt_outlined,
      Icons.facebook_rounded,
      Icons.play_arrow_rounded,
      Icons.alternate_email_rounded,
    ];
    return Column(
      children: [
        Text('Follow us on',
            style: context.textStyles.bodySmall
                ?.copyWith(color: context.colors.muted)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: icons
              .map((icon) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: context.colors.ink,
                      child: Icon(icon, size: 16, color: Colors.white),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
