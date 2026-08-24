import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../blocked_users/presentation/controllers/blocked_users_controller.dart';
import '../../../favourites/presentation/controllers/favourites_controller.dart';
import '../../data/api_profile_detail_repository.dart';

/// Mirrors backend/internal/reports/taxonomy.go's reasonCatalog — keep
/// these two lists in sync when adding a reason. (code, label) pairs,
/// grouped under a category header for the picker below.
class _ReportCategory {
  final String title;
  final IconData icon;
  final List<(String code, String label)> reasons;
  const _ReportCategory(this.title, this.icon, this.reasons);
}

const _reportCategories = [
  _ReportCategory('Profile Reports', Icons.person_outline_rounded, [
    ('fake_profile', 'Fake / misleading profile'),
    ('impersonation', 'Impersonating someone'),
    ('wrong_photos', 'Wrong photos'),
    ('someone_elses_photos', 'Photos of someone else'),
    ('incorrect_age', 'Age is incorrect'),
    ('incorrect_marital_status', 'Marital status is incorrect'),
    ('wrong_occupation_education', 'Wrong occupation / education'),
    ('suspicious_profile', 'Suspicious profile'),
    ('commercial_profile', 'Commercial / promotional profile'),
    ('asking_for_money', 'Asking for money'),
    ('scam_fraud', 'Scam / fraud'),
    ('harassment', 'Harassment'),
    ('inappropriate_content', 'Inappropriate content'),
  ]),
  _ReportCategory('Chat / Message Reports', Icons.chat_bubble_outline_rounded, [
    ('sharing_phone_number', 'Sharing phone number'),
    ('sharing_whatsapp_number', 'Sharing WhatsApp number'),
    ('sharing_email_address', 'Sharing email address'),
    ('sharing_social_handle', 'Sharing social-media handle'),
    ('asking_move_outside_app', 'Asking to move conversation outside Vivah'),
    ('asking_for_money', 'Asking for money'),
    ('scam_fraud', 'Financial scam'),
    ('abusive_language', 'Abusive language'),
    ('sexual_messages', 'Sexual / inappropriate messages'),
    ('harassment', 'Harassment'),
    ('threats', 'Threats'),
    ('spam', 'Spam'),
    ('suspicious_links', 'Suspicious links'),
  ]),
  _ReportCategory('Photo Reports', Icons.photo_outlined, [
    ('nudity_explicit', 'Nudity / sexually explicit'),
    ('inappropriate_photo', 'Inappropriate photo'),
    ('fake_photo', 'Fake photo'),
    ('celebrity_photo', "Celebrity / someone else's photo"),
    ('group_photo_confusion', 'Group photo causing confusion'),
    ('offensive_content', 'Offensive content'),
    ('misleading_photo', 'Misleading photo'),
    ('ai_generated_photo', 'AI-generated/deceptive photo'),
  ]),
  _ReportCategory('Serious Safety Reports', Icons.gpp_maybe_outlined, [
    ('financial_fraud', 'Financial fraud'),
    ('extortion_blackmail', 'Extortion / blackmail'),
    ('threats', 'Threats'),
    ('stalking', 'Stalking'),
    ('identity_theft', 'Identity theft'),
    ('underage_user', 'Underage user'),
    ('sexual_exploitation', 'Sexual exploitation'),
    ('human_trafficking', 'Human trafficking concern'),
    ('serious_harassment', 'Serious harassment'),
  ]),
  _ReportCategory('Money / Fraud Reports', Icons.currency_rupee_rounded, [
    ('asking_for_loan', 'Asking for loan'),
    ('asking_financial_help', 'Asking for financial help'),
    ('investment_scheme', 'Investment scheme'),
    ('upi_payment_request', 'UPI/payment request'),
    ('fake_emergency', 'Fake emergency'),
    ('loan_financial_scam', 'Loan/financial scam'),
    ('requesting_otp_pin_password', 'Requesting OTP/PIN/password'),
    ('suspicious_bank_details', 'Suspicious bank details'),
  ]),
];

/// "More" menu on the profile-detail screen (and chat window's own "More"):
/// favourite toggle, report, block/unblock. Block is a semi-destructive
/// action (they immediately lose access to message you or view your
/// profile) so it goes behind a confirmation dialog rather than firing on
/// a single tap, and — since the profile/chat this sheet was opened from
/// becomes unreachable once blocked — [onBlocked] lets the caller navigate
/// somewhere sensible after a successful block instead of leaving a dead
/// screen behind. [isBlocked] switches the row to Unblock (no confirmation
/// needed — restoring access isn't destructive) when the caller already
/// knows this member is blocked, e.g. a chat that's currently locked.
class ProfileActionsSheet extends ConsumerWidget {
  final String profileId;
  final String name;
  final bool isBlocked;
  final VoidCallback? onBlocked;

  const ProfileActionsSheet({
    super.key,
    required this.profileId,
    required this.name,
    this.isBlocked = false,
    this.onBlocked,
  });

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<(String code, String? details)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => const _ReportReasonSheet(),
    );
    if (result == null || !context.mounted) return;
    Navigator.of(context).pop(); // close the actions sheet

    final (code, details) = result;
    final reportResult = await ref
        .read(profileDetailRepositoryProvider)
        .reportProfile(profileId, code, details: details);
    if (!context.mounted) return;
    reportResult.when(
      success: (_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Reported — thanks for letting us know.'))),
      failure: (f) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3), content: Text(f.message))),
    );
  }

  Future<void> _block(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block $name?'),
        content: const Text(
            "They won't be able to message you or view your profile."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Block',
                style: TextStyle(color: dialogContext.colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref.read(blockedUsersActionsProvider).block(profileId);
    if (!context.mounted) return;

    Navigator.of(context).pop(); // close the actions sheet
    result.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              duration: const Duration(seconds: 3),
              content: Text('$name has been blocked.')),
        );
        onBlocked?.call();
      },
      failure: (f) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 3), content: Text(f.message)));
      },
    );
  }

  Future<void> _unblock(BuildContext context, WidgetRef ref) async {
    final result =
        await ref.read(blockedUsersActionsProvider).unblock(profileId);
    if (!context.mounted) return;

    Navigator.of(context).pop(); // close the actions sheet
    result.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('$name has been unblocked.')));
      },
      failure: (f) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 3), content: Text(f.message)));
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavourited = ref.watch(favouriteActionsProvider.select(
      (s) => s.favourited.contains(profileId),
    ));

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: context.colors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: Icon(
                isFavourited ? Icons.star_rounded : Icons.star_border_rounded),
            title: Text(
                isFavourited ? 'Remove from favourites' : 'Add to favourites'),
            onTap: () {
              ref
                  .read(favouriteActionsProvider.notifier)
                  .toggleFavourite(profileId);
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Report'),
            onTap: () => _report(context, ref),
          ),
          if (isBlocked)
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: const Text('Unblock'),
              onTap: () => _unblock(context, ref),
            )
          else
            ListTile(
              leading: Icon(Icons.block_rounded, color: context.colors.danger),
              title:
                  Text('Block', style: TextStyle(color: context.colors.danger)),
              onTap: () => _block(context, ref),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// Scrollable, categorized report-reason picker with a free-text "Other"
/// option — pops (reasonCode, details) once a reason is chosen, or null
/// on dismiss. "Other" requires typed details before it can be submitted
/// (the backend rejects an empty custom report), everything else submits
/// immediately on tap since the label alone is enough context.
class _ReportReasonSheet extends StatefulWidget {
  const _ReportReasonSheet();

  @override
  State<_ReportReasonSheet> createState() => _ReportReasonSheetState();
}

class _ReportReasonSheetState extends State<_ReportReasonSheet> {
  final _otherController = TextEditingController();
  bool _showOtherField = false;

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.colors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text('Report this profile',
                    style: context.textStyles.titleMedium),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  children: [
                    for (final category in _reportCategories) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: Row(
                          children: [
                            Icon(category.icon, size: 16, color: context.colors.muted),
                            const SizedBox(width: 6),
                            Text(category.title,
                                style: context.textStyles.labelSmall
                                    ?.copyWith(color: context.colors.muted)),
                          ],
                        ),
                      ),
                      for (final (code, label) in category.reasons)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(label),
                          onTap: () => Navigator.of(context).pop((code, null)),
                        ),
                      const Divider(height: AppSpacing.lg),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Row(
                        children: [
                          Icon(Icons.edit_note_rounded, size: 16, color: context.colors.muted),
                          const SizedBox(width: 6),
                          Text('Other',
                              style: context.textStyles.labelSmall
                                  ?.copyWith(color: context.colors.muted)),
                        ],
                      ),
                    ),
                    if (!_showOtherField)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Something else'),
                        onTap: () => setState(() => _showOtherField = true),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _otherController,
                              autofocus: true,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: 'Describe the issue…',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            ElevatedButton(
                              onPressed: () {
                                final details = _otherController.text.trim();
                                if (details.isEmpty) return;
                                Navigator.of(context).pop(('other', details));
                              },
                              child: const Text('Submit report'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
