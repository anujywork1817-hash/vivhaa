import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/interest.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../../../chat/data/api_chat_repository.dart';
import '../../../chat/presentation/controllers/chat_controller.dart';
import '../../../interests/presentation/controllers/interests_controller.dart';
import '../../../premium/presentation/controllers/premium_controller.dart';
import '../controllers/app_shell_controller.dart';

/// Inbox tab — Received / Accepted / Contacts / Sent / More, all backed by
/// the same interest + chat state the Interests flow already writes to.
/// Accepted splits by who accepted; More collects requests that ended
/// (declined or deleted).
class InboxTabScreen extends ConsumerStatefulWidget {
  const InboxTabScreen({super.key});

  @override
  ConsumerState<InboxTabScreen> createState() => _InboxTabScreenState();
}

class _InboxTabScreenState extends ConsumerState<InboxTabScreen> {
  @override
  Widget build(BuildContext context) {
    // The shell keeps this screen alive in an IndexedStack, so its
    // providers never naturally re-fetch on tab switch the way a fresh
    // route would. There's also no push event for "they accepted your
    // interest" — the only way to learn about it is to ask again. So:
    // re-fetch both sent and received interests every time this tab
    // becomes the active one, which is when "Accepted by Them"/"Accepted
    // by Me" actually needs to be current.
    ref.listen(appShellTabProvider, (previous, next) {
      if (next == AppTab.inbox && previous != AppTab.inbox) {
        ref.invalidate(sentInterestsProvider);
        ref.invalidate(receivedInterestsProvider);
      }
    });

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inbox'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Received'),
              Tab(text: 'Accepted'),
              Tab(text: 'Contacts'),
              Tab(text: 'Sent'),
              Tab(text: 'More'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ReceivedList(),
            _AcceptedList(),
            _ContactsList(),
            _SentList(),
            _MoreList(),
          ],
        ),
      ),
    );
  }
}

class _EmptyInbox extends ConsumerWidget {
  final String title;
  final String message;
  const _EmptyInbox({required this.title, required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EmptyState(
      icon: Icons.mail_outline_rounded,
      title: title,
      message: message,
      actionLabel: 'View My Matches',
      onAction: () =>
          ref.read(appShellTabProvider.notifier).state = AppTab.matches,
    );
  }
}

class _ReceivedList extends ConsumerWidget {
  const _ReceivedList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref
            .watch(receivedInterestsProvider)
            .valueOrNull
            ?.where((r) => r.status == InterestStatus.pending)
            .toList() ??
        [];
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(receivedInterestsProvider),
      child: records.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 80),
                _EmptyInbox(
                  title: 'No pending Requests',
                  message:
                      'Check out more Profiles and continue your Partner search.',
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: records.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) => _InboxTile(
                record: records[i],
                onTap: () =>
                    context.push(AppRoutes.interestDecisionPath(records[i].id)),
              ),
            ),
    );
  }
}

/// Accepted matches, split by who did the accepting. The distinction is
/// derivable without extra data: an accepted interest you *received* is
/// one you accepted, and an accepted interest you *sent* is one they
/// accepted.
class _AcceptedList extends ConsumerWidget {
  const _AcceptedList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acceptedByMe =
        (ref.watch(receivedInterestsProvider).valueOrNull ?? [])
            .where((r) => r.status == InterestStatus.accepted)
            .toList();
    final acceptedByThem = (ref.watch(sentInterestsProvider).valueOrNull ?? [])
        .where((r) => r.status == InterestStatus.accepted)
        .toList();

    if (acceptedByMe.isEmpty && acceptedByThem.isEmpty) {
      return const _EmptyInbox(
        title: 'No accepted matches yet',
        message:
            'Once an interest is accepted (by you or them), it shows up here.',
      );
    }

    // Pronoun comes from the other party's gender; with mixed genders a
    // neutral label is used rather than picking one.
    final genders = acceptedByThem.map((r) => r.otherGender).toSet();
    final themLabel = genders.length == 1 && acceptedByThem.isNotEmpty
        ? 'Accepted by ${_capitalise(acceptedByThem.first.objectPronoun)}'
        : 'Accepted by Them';

    final byThemSelected = ref.watch(acceptedByThemProvider);
    final records = byThemSelected ? acceptedByThem : acceptedByMe;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
          child: Row(
            children: [
              _TogglePill(
                label: '$themLabel (${acceptedByThem.length})',
                selected: byThemSelected,
                onTap: () =>
                    ref.read(acceptedByThemProvider.notifier).state = true,
              ),
              const SizedBox(width: AppSpacing.sm),
              _TogglePill(
                label: 'Accepted by Me (${acceptedByMe.length})',
                selected: !byThemSelected,
                onTap: () =>
                    ref.read(acceptedByThemProvider.notifier).state = false,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(sentInterestsProvider);
              ref.invalidate(receivedInterestsProvider);
            },
            child: records.isEmpty
                ? ListView(
                    children: [
                      SizedBox(
                          height: MediaQuery.of(context).size.height * 0.12),
                      _EmptyInbox(
                        title: byThemSelected
                            ? 'None accepted yet'
                            : "You haven't accepted any yet",
                        message: byThemSelected
                            ? 'Requests you send appear here once they accept.'
                            : 'Requests you accept from the Received tab appear here.',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                    itemCount: records.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, i) =>
                        _AcceptedCard(record: records[i]),
                  ),
          ),
        ),
      ],
    );
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// True when the Accepted tab is showing requests the other side accepted.
/// Held outside the widget so the choice survives tab switches.
final acceptedByThemProvider = StateProvider<bool>((ref) => true);

class _TogglePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TogglePill(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? context.colors.ink : context.colors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(
                color: selected ? context.colors.ink : context.colors.line),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.textStyles.bodySmall?.copyWith(
              color: selected ? Colors.white : context.colors.ink,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactsList extends ConsumerWidget {
  const _ContactsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref
            .watch(conversationsProvider)
            .valueOrNull
            ?.where((c) => c.contactShared)
            .toList() ??
        [];
    if (conversations.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(conversationsProvider),
        child: ListView(
          children: const [
            SizedBox(height: 80),
            _EmptyInbox(
              title: 'No shared contacts yet',
              message:
                  'Contact numbers you request and receive in chat appear here.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(conversationsProvider),
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: conversations.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) {
          final c = conversations[i];
          return InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            onTap: () => context.push(AppRoutes.chatWindowPath(c.id)),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: context.colors.line),
              ),
              child: Row(
                children: [
                  ProfileAvatar(name: c.withProfile.name, size: 52),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.withProfile.name,
                            style: context.textStyles.titleSmall),
                        Text('Contact number shared',
                            style: context.textStyles.bodySmall
                                ?.copyWith(color: context.colors.success)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: context.colors.muted),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

enum SentFilter { all, viewed, notViewed }

/// Which subset of sent requests the Sent tab is showing. Kept outside the
/// widget so the choice survives tab switches.
final sentFilterProvider = StateProvider<SentFilter>((ref) => SentFilter.all);

class _SentList extends ConsumerWidget {
  const _SentList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only still-pending sends belong here — once accepted it belongs
    // solely in the Accepted tab (declined likewise drops out entirely),
    // same as _ReceivedList's own pending-only filter below. Previously
    // this showed every sent interest regardless of status, so an
    // accepted one kept sitting in Sent forever in addition to appearing
    // in Accepted.
    final pending = ref
            .watch(sentInterestsProvider)
            .valueOrNull
            ?.where((r) => r.status == InterestStatus.pending)
            .toList() ??
        [];
    final filter = ref.watch(sentFilterProvider);

    final records = switch (filter) {
      SentFilter.all => pending,
      SentFilter.viewed => pending.where((r) => r.isViewed).toList(),
      SentFilter.notViewed => pending.where((r) => !r.isViewed).toList(),
    };

    // Pronoun for the filter labels, from the people actually in the list.
    final genders = pending.map((r) => r.otherGender).toSet();
    final pronoun = genders.length == 1 && pending.isNotEmpty
        ? pending.first.objectPronoun
        : 'them';

    if (pending.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(sentInterestsProvider),
        child: ListView(
          children: const [
            SizedBox(height: 80),
            _EmptyInbox(
              title: 'No interests sent yet',
              message:
                  'Interests you send from Matches or a profile show up here.',
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Text('All Requests (${records.length})',
                    style: context.textStyles.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _showFilterSheet(context, ref, filter, pronoun),
                icon: const Icon(Icons.filter_alt_outlined, size: 16),
                label: Text(switch (filter) {
                  SentFilter.all => 'FILTER',
                  SentFilter.viewed => 'VIEWED',
                  SentFilter.notViewed => 'NOT VIEWED',
                }),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusPill)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(sentInterestsProvider),
            child: records.isEmpty
                ? ListView(
                    children: [
                      SizedBox(
                          height: MediaQuery.of(context).size.height * 0.12),
                      _EmptyInbox(
                        title: filter == SentFilter.viewed
                            ? 'None viewed yet'
                            : 'Everyone has seen your requests',
                        message: filter == SentFilter.viewed
                            ? "No one has opened these requests yet. They'll move here once they do."
                            : 'All your pending requests have been viewed.',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                    itemCount: records.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, i) => _SentCard(record: records[i]),
                  ),
          ),
        ),
      ],
    );
  }

  void _showFilterSheet(
      BuildContext context, WidgetRef ref, SentFilter current, String pronoun) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in [
              (SentFilter.all, 'All Requests'),
              (SentFilter.viewed, 'Viewed by $pronoun'),
              (SentFilter.notViewed, 'Not viewed by $pronoun'),
            ])
              ListTile(
                title: Text(option.$2),
                trailing: current == option.$1
                    ? Icon(Icons.check_rounded, color: context.colors.accent)
                    : null,
                onTap: () {
                  ref.read(sentFilterProvider.notifier).state = option.$1;
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Which list the More tab is showing.
final moreShowsDeletedProvider = StateProvider<bool>((ref) => false);

/// Inbox > More: requests that ended without a match. "Requests" holds
/// declined ones (either direction); "Deleted" holds ones removed from the
/// other tabs, which are soft-deleted server-side so they remain listable.
class _MoreList extends ConsumerWidget {
  const _MoreList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showDeleted = ref.watch(moreShowsDeletedProvider);

    final declined = [
      ...(ref.watch(sentInterestsProvider).valueOrNull ?? []),
      ...(ref.watch(receivedInterestsProvider).valueOrNull ?? []),
    ].where((r) => r.status == InterestStatus.declined).toList();

    final deletedAsync = ref.watch(deletedInterestsProvider);
    final deleted = deletedAsync.valueOrNull ?? const <InterestRecord>[];
    final records = showDeleted ? deleted : declined;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
          child: Row(
            children: [
              _TogglePill(
                label: 'Requests (${declined.length})',
                selected: !showDeleted,
                onTap: () =>
                    ref.read(moreShowsDeletedProvider.notifier).state = false,
              ),
              const SizedBox(width: AppSpacing.sm),
              _TogglePill(
                label: 'Deleted (${deleted.length})',
                selected: showDeleted,
                onTap: () =>
                    ref.read(moreShowsDeletedProvider.notifier).state = true,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(deletedInterestsProvider);
              ref.invalidate(sentInterestsProvider);
              ref.invalidate(receivedInterestsProvider);
            },
            child: records.isEmpty
                ? ListView(
                    children: [
                      SizedBox(
                          height: MediaQuery.of(context).size.height * 0.12),
                      _EmptyInbox(
                        title: showDeleted
                            ? 'Nothing deleted'
                            : 'No declined requests',
                        message: showDeleted
                            ? 'Requests you delete from Sent or Accepted appear here.'
                            : "Requests that were declined show up here so you can see what happened to them.",
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                    itemCount: records.length + 1,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, i) {
                      if (i == records.length) return const _EndOfListMarker();
                      return _ClosedRequestCard(
                          record: records[i], deleted: showDeleted);
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// The "you've reached the end" marker from the reference.
class _EndOfListMarker extends StatelessWidget {
  const _EndOfListMarker();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: context.colors.success, shape: BoxShape.circle),
            child:
                const Icon(Icons.check_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text("You've viewed all Requests",
              textAlign: TextAlign.center,
              style: context.textStyles.titleSmall),
        ],
      ),
    );
  }
}

/// A request that's over — declined or deleted. Shows the outcome instead
/// of contact actions, since neither state allows contacting the member.
class _ClosedRequestCard extends StatelessWidget {
  final InterestRecord record;
  final bool deleted;
  const _ClosedRequestCard({required this.record, required this.deleted});

  @override
  Widget build(BuildContext context) {
    final profile = record.profile;
    final brief = _briefLines(profile);
    final subject = record.objectPronoun == 'her'
        ? 'She'
        : record.objectPronoun == 'him'
            ? 'He'
            : 'They';

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => context.push(AppRoutes.profileDetailPath(profile.id)),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProfileAvatar(
                      name: profile.name,
                      size: 60,
                      photoUrl: profile.photoSeed),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile.name,
                            style: context.textStyles.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        for (final line in [
                          brief.line1,
                          brief.line2,
                          brief.line3
                        ])
                          if (line.isNotEmpty)
                            Text(line,
                                style: context.textStyles.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Text(_relativeTime(record.timestamp),
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: context.colors.muted)),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: context.colors.line),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 18, color: context.colors.danger),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    deleted
                        ? 'You deleted this Request.\nThis Member cannot be contacted.'
                        : '$subject Declined your Request.\nThis Member cannot be contacted.',
                    style: context.textStyles.bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Builds the three brief lines shared by the inbox cards.
({String line1, String line2, String line3}) _briefLines(MatchProfile p) {
  return (
    line1: [
      if (p.age > 0) '${p.age} yrs',
      if (p.heightCm > 0) p.heightLabel,
      if (p.profession.isNotEmpty) p.profession,
    ].join(' · '),
    line2: [
      if (p.motherTongue != null && p.motherTongue!.isNotEmpty) p.motherTongue!,
      if (p.community != null && p.community!.isNotEmpty) p.community!,
    ].join(', '),
    line3: [
      if (p.city.isNotEmpty) p.city,
      if (p.state != null && p.state!.isNotEmpty) p.state!,
    ].join(', '),
  );
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
  if (diff.inHours < 24) {
    return diff.inHours == 1 ? 'an hour ago' : '${diff.inHours} hours ago';
  }
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 30) return '${diff.inDays} days ago';
  return '${(diff.inDays / 30).floor()} months ago';
}

/// Accepted-match card: profile brief, ⋮ menu, and the contact actions.
/// Chat is free once accepted; phone and WhatsApp need the other party's
/// number, which is premium-gated server-side — hence the upgrade prompt.
class _AcceptedCard extends ConsumerStatefulWidget {
  final InterestRecord record;
  const _AcceptedCard({required this.record});

  @override
  ConsumerState<_AcceptedCard> createState() => _AcceptedCardState();
}

class _AcceptedCardState extends ConsumerState<_AcceptedCard> {
  bool _busy = false;

  Future<void> _delete() async {
    final name = widget.record.profile.name.split(' ').first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this match?'),
        content: Text('$name will be removed from your accepted list.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Remove',
                style: TextStyle(color: dialogContext.colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final failure =
        await ref.read(interestsActionsProvider).withdraw(widget.record.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(failure.message)));
    }
  }

  /// Contact numbers are never revealed on demand — this member has to
  /// explicitly agree to share theirs. Sends a contact-request message
  /// (visible to them as an Accept/Decline prompt in chat) and opens the
  /// conversation so the requester can see the outcome as soon as they
  /// respond, instead of getting the number silently and instantly.
  Future<void> _requestContact() async {
    final conversation =
        ref.read(conversationForProfileProvider(widget.record.profile.id));
    if (conversation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(
              'Send them a chat message first, then you can request their contact number.')));
      return;
    }

    setState(() => _busy = true);
    final result = await ref
        .read(chatRepositoryProvider)
        .requestContactNumber(conversation.id);
    if (!mounted) return;
    setState(() => _busy = false);

    result.when(
      success: (_) {
        context.push(AppRoutes.chatWindowPath(conversation.id));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(
                "Contact request sent — you'll see their response in chat.")));
      },
      failure: (f) {
        // Already has a pending request with them — just take the user to
        // chat to see it, rather than surfacing this as an error.
        if (f.message.contains('pending')) {
          context.push(AppRoutes.chatWindowPath(conversation.id));
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 3), content: Text(f.message)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final profile = record.profile;
    final brief = _briefLines(profile);
    final conversation = ref.watch(conversationForProfileProvider(profile.id));
    final isPremium =
        ref.watch(mySubscriptionProvider).valueOrNull?.isPremium ?? false;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => context.push(AppRoutes.profileDetailPath(profile.id)),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProfileAvatar(
                      name: profile.name,
                      size: 60,
                      photoUrl: profile.photoSeed),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(profile.name,
                                  style: context.textStyles.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (profile.verified) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.verified_rounded,
                                  size: 14, color: context.colors.accent),
                            ],
                          ],
                        ),
                        for (final line in [
                          brief.line1,
                          brief.line2,
                          brief.line3
                        ])
                          if (line.isNotEmpty)
                            Text(line,
                                style: context.textStyles.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_relativeTime(record.timestamp),
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: context.colors.muted)),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_vert_rounded, size: 20),
                        enabled: !_busy,
                        onSelected: (v) {
                          if (v == 'profile') {
                            context
                                .push(AppRoutes.profileDetailPath(profile.id));
                          }
                          if (v == 'delete') _delete();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'profile', child: Text('View profile')),
                          PopupMenuItem(
                              value: 'delete', child: Text('Remove match')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!isPremium) ...[
            Divider(height: 1, color: context.colors.line),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text('To view a shared contact number, ',
                        style: context.textStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  InkWell(
                    onTap: () => context.push(AppRoutes.premiumPaywall),
                    child: Text('Upgrade ›',
                        style: context.textStyles.bodySmall?.copyWith(
                            color: context.colors.accent,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
          Divider(height: 1, color: context.colors.line),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CardAction(
                  icon: Icons.chat_bubble_rounded,
                  label: 'Chat',
                  color: context.colors.accent,
                  // This card only exists for an accepted interest, so chat is
                  // open by definition. Keying off the partner's user id goes
                  // straight there; the conversation lookup is a fallback,
                  // since it needs the list to have loaded and to have matched
                  // on profile id — the reason this used to tell people to
                  // pull to refresh.
                  onTap: _busy
                      ? null
                      : () {
                          final target =
                              widget.record.partnerUserId ?? conversation?.id;
                          if (target == null) return;
                          context.push(AppRoutes.chatWindowPath(target));
                        },
                ),
                _CardAction(
                  icon: Icons.contact_phone_outlined,
                  label: 'Request Contact',
                  color: context.colors.gold,
                  onTap: _busy ? null : _requestContact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sent-request card: photo, name, a short profile brief, when it was
/// sent, whether it's been viewed, and the actions from the reference —
/// Remind / Chat / Contact, plus a ⋮ menu for Remind and Delete.
class _SentCard extends ConsumerStatefulWidget {
  final InterestRecord record;
  const _SentCard({required this.record});

  @override
  ConsumerState<_SentCard> createState() => _SentCardState();
}

class _SentCardState extends ConsumerState<_SentCard> {
  bool _busy = false;

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      return diff.inHours == 1 ? 'an hour ago' : '${diff.inHours} hours ago';
    }
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 30) return '${diff.inDays} days ago';
    return '${(diff.inDays / 30).floor()} months ago';
  }

  Future<void> _remind() async {
    setState(() => _busy = true);
    final failure =
        await ref.read(interestsActionsProvider).remind(widget.record.id);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      content: Text(failure?.message ??
          'Reminder sent to ${widget.record.profile.name.split(' ').first}.'),
    ));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this request?'),
        content: Text(
            'Your interest in ${widget.record.profile.name.split(' ').first} will be withdrawn. '
            'You can send it again later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete',
                style: TextStyle(color: dialogContext.colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final failure =
        await ref.read(interestsActionsProvider).withdraw(widget.record.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final profile = record.profile;
    final conversation = ref.watch(conversationForProfileProvider(profile.id));

    final line1 = [
      if (profile.age > 0) '${profile.age} yrs',
      if (profile.heightCm > 0) profile.heightLabel,
      if (profile.profession.isNotEmpty) profile.profession,
    ].join(' · ');
    final line2 = [
      if (profile.motherTongue != null && profile.motherTongue!.isNotEmpty)
        profile.motherTongue!,
      if (profile.community != null && profile.community!.isNotEmpty)
        profile.community!,
    ].join(', ');
    final line3 = [
      if (profile.city.isNotEmpty) profile.city,
      if (profile.state != null && profile.state!.isNotEmpty) profile.state!,
    ].join(', ');

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => context.push(AppRoutes.profileDetailPath(profile.id)),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProfileAvatar(
                      name: profile.name,
                      size: 60,
                      photoUrl: profile.photoSeed),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(profile.name,
                                  style: context.textStyles.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (profile.verified) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.verified_rounded,
                                  size: 14, color: context.colors.accent),
                            ],
                          ],
                        ),
                        if (line1.isNotEmpty)
                          Text(line1,
                              style: context.textStyles.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        if (line2.isNotEmpty)
                          Text(line2,
                              style: context.textStyles.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        if (line3.isNotEmpty)
                          Text(line3,
                              style: context.textStyles.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_relative(record.timestamp),
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: context.colors.muted)),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_vert_rounded, size: 20),
                        enabled: !_busy,
                        onSelected: (value) {
                          if (value == 'remind') _remind();
                          if (value == 'delete') _delete();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'remind',
                              child: Text('Send request again')),
                          PopupMenuItem(
                              value: 'delete', child: Text('Delete request')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: context.colors.line),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  record.isViewed
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_outlined,
                  size: 15,
                  color: record.isViewed
                      ? context.colors.success
                      : context.colors.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    record.isViewed
                        ? 'Viewed by ${record.objectPronoun}'
                        : 'Not viewed by ${record.objectPronoun} yet',
                    style: context.textStyles.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.line),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CardAction(
                  icon: Icons.notifications_active_rounded,
                  label: 'Remind',
                  color: context.colors.accent,
                  onTap: _busy ? null : _remind,
                ),
                _CardAction(
                  icon: Icons.chat_bubble_rounded,
                  label: 'Chat',
                  color: context.colors.muted,
                  // Unlocked the moment they accept — the record's own status
                  // is the authority, not whether the conversation list has
                  // caught up yet.
                  onTap: () {
                    final target =
                        widget.record.status == InterestStatus.accepted
                            ? (widget.record.partnerUserId ?? conversation?.id)
                            : null;
                    if (target == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          duration: const Duration(seconds: 3),
                          content: Text(
                              'Chat opens once they accept your interest.')));
                      return;
                    }
                    context.push(AppRoutes.chatWindowPath(target));
                  },
                ),
                _CardAction(
                  icon: Icons.call_rounded,
                  label: 'Contact',
                  color: context.colors.muted,
                  onTap: () =>
                      context.push(AppRoutes.profileDetailPath(profile.id)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _CardAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 4),
            Text(label, style: context.textStyles.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _InboxTile extends StatelessWidget {
  final InterestRecord record;
  final VoidCallback onTap;
  const _InboxTile({required this.record, required this.onTap});

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
            ProfileAvatar(name: record.profile.name, size: 52),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${record.profile.name}, ${record.profile.age}',
                      style: context.textStyles.titleSmall),
                  Text('${record.profile.profession} · ${record.profile.city}',
                      style: context.textStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
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
