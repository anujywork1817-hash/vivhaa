import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../../../../shared/widgets/feedback/shimmer_box.dart';
import '../../../../shared/widgets/misc/locked_profile_photo.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../../../chat/presentation/controllers/chat_controller.dart';
import '../../../interests/presentation/controllers/interest_actions_controller.dart';
import '../../../interests/presentation/controllers/interests_controller.dart';
import '../../../profile_detail/presentation/widgets/profile_actions_sheet.dart';
import '../controllers/app_shell_controller.dart';
import '../controllers/dashboard_controller.dart';
import '../controllers/location_controller.dart';
import '../controllers/matches_filter_controller.dart';

/// Matches tab — horizontally scrollable filter chips (Search / New /
/// Daily / More) switch the underlying list. The body stacks two
/// sections: a horizontal rail of preference-matched profiles, then the
/// selected filter's results as a vertical feed of full-bleed cards.
class MatchesTabScreen extends ConsumerWidget {
  const MatchesTabScreen({super.key});

  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Advanced Search'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push(AppRoutes.advancedSearch);
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_border_rounded),
              title: const Text('Saved Searches'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push(AppRoutes.savedSearches);
              },
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Search by Profile ID'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push(AppRoutes.searchByProfileId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swipe_rounded),
              title: const Text('Discover (swipe)'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push(AppRoutes.discover);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(matchesFilterProvider);
    final newAsync = ref.watch(newMembersProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.menu_rounded),
        title: const Text('Matches'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          const SizedBox(height: AppSpacing.sm),
          const _MatchesSearchBarEntry(),
          const SizedBox(height: AppSpacing.sm),
          // Horizontally scrollable: the chips are wider than the screen
          // on smaller devices (they carry live counts, so their width
          // isn't fixed), which is what produced the "RIGHT OVERFLOWED"
          // stripe and made the row feel unswipeable.
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
              children: [
                _FilterChip(
                  icon: Icons.badge_outlined,
                  label: 'Search by ID',
                  selected: false,
                  onTap: () => context.push(AppRoutes.searchByProfileId),
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterChip(
                  label: 'New (${newAsync.valueOrNull?.length ?? 0})',
                  selected: filter == MatchesFilter.newMembers,
                  onTap: () => ref.read(matchesFilterProvider.notifier).state =
                      MatchesFilter.newMembers,
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterChip(
                  icon: Icons.groups_rounded,
                  label: 'All Matches',
                  selected: filter == MatchesFilter.all,
                  onTap: () => ref.read(matchesFilterProvider.notifier).state =
                      MatchesFilter.all,
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterChip(
                  icon: Icons.near_me_rounded,
                  label: 'Near Me',
                  selected: filter == MatchesFilter.nearby,
                  onTap: () => ref.read(matchesFilterProvider.notifier).state =
                      MatchesFilter.nearby,
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterChip(
                  icon: Icons.tune_rounded,
                  label: 'More',
                  selected: false,
                  onTap: () => _showMoreSheet(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: filter == MatchesFilter.nearby
                ? const _NearbyMatchesBody()
                : _MatchesBody(
                    listAsync: switch (filter) {
                      MatchesFilter.newMembers => newAsync,
                      MatchesFilter.all => ref.watch(allMatchesProvider),
                      MatchesFilter.nearby => newAsync, // unreachable
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label,
      this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Selected = Primary Rose (fill + border), matching "active tabs" in
    // the design system — previously selected chips went near-black,
    // which read as a totally different (and heavier) color language
    // than the rest of the app's rose accent.
    return ChoiceChip(
      avatar: icon != null
          ? Icon(icon, size: 16, color: selected ? Colors.white : null)
          : null,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: context.colors.accent,
      backgroundColor: context.colors.surface,
      labelStyle: TextStyle(
          color: selected ? Colors.white : context.colors.ink,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
      side: BorderSide(
          color: selected ? context.colors.accent : context.colors.line),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill)),
    );
  }
}

/// Two stacked sections in one scroll view: a horizontal rail of
/// preference-matched profiles at the top, then the selected filter's
/// results as a vertical feed of full-bleed cards.
class _MatchesBody extends ConsumerWidget {
  final AsyncValue<List<MatchProfile>> listAsync;
  const _MatchesBody({required this.listAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(recommendedMatchesProvider);
    final prefs = prefsAsync.valueOrNull ?? const <MatchProfile>[];

    // The rail's text block scales with the font-size preference, so its
    // height is derived rather than hard-coded (a fixed height is exactly
    // what overflowed elsewhere).
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    final railHeight = 112 + 116 * textScale;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(recommendedMatchesProvider);
        ref.invalidate(newMembersProvider);
        ref.invalidate(todayMatchesProvider);
      },
      child: CustomScrollView(
        slivers: [
          // The section always renders. Hiding it when the rail happens to
          // be empty (e.g. you've already sent an interest to everyone who
          // matches, which the engine excludes) is indistinguishable from
          // the feature being missing — so say why it's empty instead.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Matching your Preferences',
                        style: context.textStyles.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  TextButton(
                    onPressed: () =>
                        context.push(AppRoutes.partnerPreferences, extra: true),
                    child: const Text('Edit'),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: prefsAsync.isLoading
                ? SizedBox(
                    height: railHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      itemCount: 3,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: AppSpacing.md),
                      itemBuilder: (_, __) => ShimmerBox(
                          width: 168,
                          height: railHeight,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusLg)),
                    ),
                  )
                : prefs.isEmpty
                    ? _RailEmptyState(errored: prefsAsync.hasError)
                    // A fixed-height SizedBox forces every card to that exact
                    // height (a horizontal ListView's cross axis is always
                    // tight to its container) — if real content (a 2-line
                    // name/details wrap, a taller button at large font
                    // scale) needs even a pixel more, it overflows instead
                    // of the row just growing to fit. IntrinsicHeight lets
                    // the row size itself from its tallest card instead of
                    // a hard-coded/estimated height.
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < prefs.length; i++) ...[
                                if (i > 0) const SizedBox(width: AppSpacing.md),
                                _CompactMatchCard(profile: prefs[i]),
                              ],
                            ],
                          ),
                        ),
                      ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
          ...listAsync.when(
            loading: () => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: ShimmerBox(
                      width: double.infinity,
                      height: 420,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
                ),
              ),
            ],
            error: (e, st) => [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                    child: Text('Something went wrong.',
                        style: TextStyle(color: context.colors.muted))),
              ),
            ],
            data: (profiles) {
              if (profiles.isEmpty) {
                return [
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'No matches here yet',
                      message:
                          'Check back soon, or try Search to widen your criteria.',
                    ),
                  ),
                ];
              }
              return [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                  sliver: _MatchGrid(profiles: profiles),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }
}

/// Shown in place of the rail when there's nothing to recommend. The
/// common cause isn't an error: the engine skips anyone you've already
/// sent an interest to, so an active member eventually exhausts the pool.
class _RailEmptyState extends StatelessWidget {
  final bool errored;
  const _RailEmptyState({required this.errored});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: context.colors.line),
        ),
        child: Row(
          children: [
            Icon(errored ? Icons.error_outline_rounded : Icons.done_all_rounded,
                color: context.colors.muted, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                errored
                    ? "Couldn't load your preference matches. Pull down to retry."
                    : "You've connected with everyone matching your preferences. "
                        'Widen them to see more.',
                style: context.textStyles.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact card for the horizontal preferences rail — circular photo,
/// name, a one-line summary, and a connect action.
class _CompactMatchCard extends ConsumerWidget {
  final MatchProfile profile;
  const _CompactMatchCard({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isInterested = ref.watch(isInterestSentProvider(profile.id));
    final isConnected =
        ref.watch(conversationForProfileProvider(profile.id)) != null;
    final showLocked = profile.photoLocked && !isConnected;

    // Two lines, as in the reference: physical/language details on the
    // first, location on the second. Each part is dropped when absent
    // rather than leaving stray commas.
    final line1 = [
      if (profile.age > 0) '${profile.age} yrs',
      if (profile.heightCm > 0) profile.heightLabel,
      if (profile.motherTongue != null && profile.motherTongue!.isNotEmpty)
        profile.motherTongue!,
    ].join(', ');
    final line2 = [
      if (profile.city.isNotEmpty) profile.city,
      if (profile.state != null && profile.state!.isNotEmpty) profile.state!,
    ].join(', ');

    return SizedBox(
      width: 168,
      child: Material(
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
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The reference badges the other member's paid tier here.
                // We have no way to know another member's plan, so this
                // shows verification status instead — real data rather
                // than a badge that would be identical on every card.
                ConstrainedBox(
                  // A hard `height: 18` here would clip/overflow at larger
                  // font scales, since the label text grows but the box
                  // wouldn't — minHeight keeps unverified cards' spacing
                  // consistent while letting verified cards grow as needed.
                  constraints: const BoxConstraints(minHeight: 18),
                  child: profile.verified
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.verified_rounded,
                                size: 13, color: context.colors.gold),
                            const SizedBox(width: 3),
                            Text('Verified',
                                style: context.textStyles.labelSmall
                                    ?.copyWith(color: context.colors.gold)),
                          ],
                        )
                      : null,
                ),
                const SizedBox(height: 2),
                if (showLocked)
                  ClipOval(
                    child: SizedBox(
                        width: 72,
                        height: 72,
                        child: LockedProfilePhoto(name: profile.name)),
                  )
                else
                  ProfileAvatar(
                      name: profile.name,
                      size: 72,
                      photoUrl: profile.photoSeed),
                const SizedBox(height: 8),
                Text(profile.name,
                    style: context.textStyles.titleSmall,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                if (line1.isNotEmpty)
                  Text(line1,
                      style: context.textStyles.bodySmall,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                if (line2.isNotEmpty)
                  Text(line2,
                      style: context.textStyles.bodySmall,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
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
                                      duration: const Duration(seconds: 3),
                                      content: Text(failure.message)));
                            }
                          },
                    icon: Icon(Icons.check_rounded,
                        size: 14,
                        color: isInterested
                            ? context.colors.muted
                            : context.colors.accent),
                    label: Text(isInterested ? 'Requested' : 'Connect Now',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      // Flutter's default tap-target padding pads the
                      // button's layout size beyond `minimumSize` to meet
                      // the platform's minimum touch area — inside a card
                      // with a tightly budgeted height, that invisible
                      // padding is exactly the kind of few-pixel margin
                      // that overflows. shrinkWrap keeps the rendered size
                      // equal to minimumSize.
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusPill)),
                    ),
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

/// Responsive 2-column grid of [_MatchGridCard]s. `mainAxisExtent` (not an
/// aspect ratio) so the row height is explicit and predictable, while
/// everything inside each card still uses Expanded/maxLines so text never
/// overflows that budget regardless of font-scale settings.
class _MatchGrid extends StatelessWidget {
  final List<MatchProfile> profiles;
  const _MatchGrid({required this.profiles});

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    final cardHeight = 218 + 108 * textScale;

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        mainAxisExtent: cardHeight,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) => _MatchGridCard(profile: profiles[i]),
        childCount: profiles.length,
      ),
    );
  }
}

/// The one reusable match card used everywhere a profile needs to show up
/// in a grid (Matches results, Near Me): photo, verification badge,
/// shortlist toggle, name/age, height + mother tongue, city/state, an
/// optional compatibility badge, a Connect Now action, and an overflow
/// menu for the same favourite/report sheet used elsewhere.
class _MatchGridCard extends ConsumerWidget {
  final MatchProfile profile;
  const _MatchGridCard({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isInterested = ref.watch(isInterestSentProvider(profile.id));
    final isConnected =
        ref.watch(conversationForProfileProvider(profile.id)) != null;
    final showLocked = profile.photoLocked && !isConnected;
    final isShortlisted = ref.watch(interestActionsProvider
        .select((s) => s.shortlisted.contains(profile.id)));

    final metaLine = [
      if (profile.age > 0) '${profile.age} yrs',
      if (profile.heightCm > 0) profile.heightLabel,
      if (profile.motherTongue != null && profile.motherTongue!.isNotEmpty)
        profile.motherTongue!,
    ].join(', ');
    final locationLine = [
      if (profile.city.isNotEmpty) profile.city,
      if (profile.state != null && profile.state!.isNotEmpty) profile.state!,
    ].join(', ');

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                      child: showLocked
                          ? LockedProfilePhoto(name: profile.name)
                          : ProfileAvatar(
                              name: profile.name,
                              size: double.infinity,
                              borderRadius: BorderRadius.zero,
                              photoUrl: profile.photoSeed),
                    ),
                    if (profile.matchScore > 0 || profile.distanceKm != null)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (profile.matchScore > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusPill),
                                ),
                                child: Text(
                                    '${profile.matchScore.round()}% match',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600)),
                              ),
                            if (profile.matchScore > 0 &&
                                profile.distanceKm != null)
                              const SizedBox(height: 4),
                            if (profile.distanceKm != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusPill),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.place_rounded,
                                        size: 10, color: Colors.white),
                                    const SizedBox(width: 2),
                                    Text(
                                        profile.distanceKm! < 1
                                            ? '${(profile.distanceKm! * 1000).round()} m'
                                            : '${profile.distanceKm!.toStringAsFixed(1)} km',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: _RoundIconButton(
                        icon: isShortlisted
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: isShortlisted
                            ? context.colors.accent
                            : Colors.white,
                        background: Colors.black.withValues(alpha: 0.35),
                        onTap: () => ref
                            .read(interestActionsProvider.notifier)
                            .toggleShortlist(profile.id),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm, 8, 4, AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(profile.name,
                              style: context.textStyles.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (profile.verified)
                          Padding(
                            padding: const EdgeInsets.only(left: 3),
                            child: Icon(Icons.verified_rounded,
                                size: 14, color: context.colors.accent),
                          ),
                        InkWell(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSm),
                          onTap: () => showModalBottomSheet(
                            context: context,
                            builder: (_) => ProfileActionsSheet(
                                profileId: profile.id, name: profile.name),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(Icons.more_vert_rounded,
                                size: 16, color: context.colors.muted),
                          ),
                        ),
                      ],
                    ),
                    if (metaLine.isNotEmpty)
                      Text(metaLine,
                          style: context.textStyles.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    if (locationLine.isNotEmpty)
                      Text(locationLine,
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: context.colors.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: isInterested
                            ? null
                            : () async {
                                final failure = await ref
                                    .read(interestsActionsProvider)
                                    .send(profile);
                                if (!context.mounted) return;
                                if (failure != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          duration: const Duration(seconds: 3),
                                          content: Text(failure.message)));
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    duration: const Duration(seconds: 3),
                                    content: Text(
                                        'Interest sent to ${profile.name}.'),
                                    action: SnackBarAction(
                                      label: 'VIEW',
                                      onPressed: () {
                                        ref
                                            .read(appShellTabProvider.notifier)
                                            .state = AppTab.inbox;
                                      },
                                    ),
                                  ),
                                );
                              },
                        icon: Icon(
                            isInterested
                                ? Icons.check_rounded
                                : Icons.favorite_rounded,
                            size: 13),
                        label: Text(isInterested ? 'Requested' : 'Connect Now',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
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
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback onTap;
  const _RoundIconButton({
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

/// "Near Me" tab body — resolves the device's GPS position (asking for
/// permission the first time), shares it with the backend, and lists
/// nearby members sorted by distance. Kept separate from [_MatchesBody]
/// because it needs its own permission/service-disabled recovery UI
/// instead of the generic "something went wrong" error state.
class _NearbyMatchesBody extends ConsumerWidget {
  const _NearbyMatchesBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearbyAsync = ref.watch(nearbyMatchesProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(nearbyMatchesProvider),
      child: nearbyAsync.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            ShimmerBox(
                width: double.infinity,
                height: 440,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
          ],
        ),
        error: (e, st) => _NearbyErrorState(error: e),
        data: (profiles) {
          if (profiles.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 80),
                EmptyState(
                  icon: Icons.near_me_outlined,
                  title: 'No one nearby yet',
                  message:
                      'No members within range have shared their location. Check back later.',
                ),
              ],
            );
          }
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                sliver: _MatchGrid(profiles: profiles),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NearbyErrorState extends ConsumerWidget {
  final Object error;
  const _NearbyErrorState({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    IconData icon = Icons.error_outline_rounded;
    String title = 'Something went wrong';
    String message = "Couldn't load nearby matches. Pull down to retry.";
    String actionLabel;
    VoidCallback action;

    if (error is LocationUnavailableException) {
      switch ((error as LocationUnavailableException).reason) {
        case LocationFailureReason.serviceDisabled:
          icon = Icons.location_off_rounded;
          title = 'Location is turned off';
          message = 'Turn on location services to see members near you.';
          actionLabel = 'Open location settings';
          action = () => Geolocator.openLocationSettings();
          break;
        case LocationFailureReason.permissionDenied:
          icon = Icons.location_disabled_rounded;
          title = 'Location permission needed';
          message =
              'Allow location access so we can show you matches near you.';
          actionLabel = 'Allow location';
          action = () => ref.invalidate(nearbyMatchesProvider);
          break;
        case LocationFailureReason.permissionDeniedForever:
          icon = Icons.location_disabled_rounded;
          title = 'Location permission blocked';
          message =
              'You previously denied location access. Enable it in app settings to use Near Me.';
          actionLabel = 'Open app settings';
          action = () => Geolocator.openAppSettings();
          break;
      }
    } else {
      actionLabel = 'Retry';
      action = () => ref.invalidate(nearbyMatchesProvider);
    }

    return ListView(
      children: [
        const SizedBox(height: 80),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            children: [
              Icon(icon, size: 48, color: context.colors.muted),
              const SizedBox(height: AppSpacing.md),
              Text(title,
                  style: context.textStyles.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              Text(message,
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.colors.muted),
                  textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: action, child: Text(actionLabel)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tappable search entry, same pattern/destination as Home's own search
/// bar (AppRoutes.basicSearch) — Matches previously had no way to search
/// by name/city/profession at all, only the ID-specific chip and the
/// filter-heavy Advanced Search buried in the "More" sheet.
class _MatchesSearchBarEntry extends StatelessWidget {
  const _MatchesSearchBarEntry();

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
