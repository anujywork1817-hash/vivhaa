import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/chat_message.dart';
import '../../../../shared/models/conversation.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../../../calls/presentation/controllers/call_controller.dart';
import '../../../calls/presentation/screens/active_call_screen.dart';
import '../../../premium/presentation/controllers/premium_controller.dart';
import '../../../profile_detail/presentation/widgets/profile_actions_sheet.dart';
import '../controllers/chat_controller.dart';

class ChatWindowScreen extends ConsumerStatefulWidget {
  final String conversationId;
  const ChatWindowScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatWindowScreen> createState() => _ChatWindowScreenState();
}

enum _AttachChoice { gallery, camera, document }

class _ChatWindowScreenState extends ConsumerState<ChatWindowScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    final replyTarget = ref.read(replyTargetProvider(widget.conversationId));
    final failure = await ref
        .read(messagesControllerProvider(widget.conversationId).notifier)
        .send(text, replyToMessageId: replyTarget?.id);
    if (!mounted) return;
    if (failure == null) {
      // Only clear on success — losing what was typed on a failed send
      // (e.g. a premium_required rejection) would force the member to
      // retype it.
      _textController.clear();
      ref.read(replyTargetProvider(widget.conversationId).notifier).state =
          null;
      _scrollToBottom();
      return;
    }
    if (failure.type == AppFailureType.premiumRequired) {
      _showUpgradePrompt(failure.message);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(failure.message)));
    }
  }

  void _showUpgradePrompt(String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Upgrade to Premium'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.push(AppRoutes.premiumPaywall);
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  Future<void> _startCall(Conversation conversation,
      {bool isVideo = true}) async {
    if (ref.read(callControllerProvider).isActive) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: const Duration(seconds: 3),
          content: Text("You're already on a call.")));
      return;
    }
    unawaited(ref.read(callControllerProvider.notifier).startCall(
          // conversation.id is the partner's *user* ID (what the backend's
          // call signaling keys on) — conversation.withProfile.id is their
          // *profile* ID, used for navigation elsewhere. Mixing these up
          // would send call:initiate to the wrong identifier entirely.
          peerUserId: conversation.id,
          peerName: conversation.withProfile.name,
          peerPhotoUrl: conversation.withProfile.photoSeed,
          isVideo: isVideo,
        ));
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ActiveCallScreen()),
    );
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<_AttachChoice>(
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
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () => Navigator.of(sheetContext).pop(_AttachChoice.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.of(sheetContext).pop(_AttachChoice.camera),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Document'),
              onTap: () => Navigator.of(sheetContext).pop(_AttachChoice.document),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    List<int>? bytes;
    String? filename;
    try {
      switch (choice) {
        case _AttachChoice.gallery:
        case _AttachChoice.camera:
          final picked = await ImagePicker().pickImage(
            source: choice == _AttachChoice.camera ? ImageSource.camera : ImageSource.gallery,
            imageQuality: 85,
          );
          if (picked == null) return;
          bytes = await picked.readAsBytes();
          filename = picked.name.isNotEmpty ? picked.name : 'photo.jpg';
        case _AttachChoice.document:
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['pdf', 'doc', 'docx'],
            withData: true,
          );
          final file = result?.files.singleOrNull;
          if (file?.bytes == null) return;
          bytes = file!.bytes;
          filename = file.name;
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 3), content: Text('Could not open the picker.')));
      return;
    }
    if (bytes == null || !mounted) return;

    final failure = await ref
        .read(messagesControllerProvider(widget.conversationId).notifier)
        .sendAttachment(bytes, filename);
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3), content: Text(failure.message)));
    } else {
      _scrollToBottom();
    }
  }

  Future<void> _requestContact() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request contact number?'),
        content: const Text(
            "They'll see that you'd like to continue the conversation over phone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Request')),
        ],
      ),
    );
    if (confirmed != true) return;
    final failure = await ref
        .read(messagesControllerProvider(widget.conversationId).notifier)
        .requestContactNumber();
    if (failure != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(failure.message)));
    }
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ref
        .watch(conversationsProvider)
        .valueOrNull
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final messages =
        ref.watch(messagesControllerProvider(widget.conversationId));
    // Free members can read/open conversations and accept/decline
    // interests freely — only sending a new message is gated. Defaults to
    // allowing the composer while the subscription is still loading (or
    // failed to load) rather than flashing the upgrade banner; a stale
    // premium_required response from an actual send is still caught as a
    // safety net in _send().
    final isPremium =
        ref.watch(mySubscriptionProvider).valueOrNull?.isPremium ?? true;
    final replyTarget = ref.watch(replyTargetProvider(widget.conversationId));
    final partnerName = conversation?.withProfile.name ?? 'Member';

    ref.listen(messagesControllerProvider(widget.conversationId),
        (_, __) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: conversation == null
            ? const Text('Chat')
            : Row(
                children: [
                  ProfileAvatar(name: conversation.withProfile.name, size: 34),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(conversation.withProfile.name,
                        style: context.textStyles.titleMedium,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
        actions: [
          if (conversation != null && !conversation.isBlocked) ...[
            IconButton(
              icon: const Icon(Icons.call_rounded),
              tooltip: 'Voice call',
              onPressed: () => _startCall(conversation, isVideo: false),
            ),
            IconButton(
              icon: const Icon(Icons.videocam_rounded),
              tooltip: 'Video call',
              onPressed: () => _startCall(conversation),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'More',
            onPressed: conversation == null
                ? null
                : () => showModalBottomSheet(
                      context: context,
                      builder: (_) => ProfileActionsSheet(
                        profileId: conversation.withProfile.id,
                        name: conversation.withProfile.name,
                        isBlocked: conversation.isBlocked,
                        onBlocked: () => Navigator.of(context).pop(),
                      ),
                    ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: messages.length,
              itemBuilder: (context, i) => _MessageBubble(
                message: messages[i],
                conversationId: widget.conversationId,
                partnerName: partnerName,
                onReply: () => ref
                    .read(replyTargetProvider(widget.conversationId).notifier)
                    .state = messages[i],
              ),
            ),
          ),
          if (conversation?.isBlocked ?? false)
            const _BlockedComposerBar()
          else if (!isPremium)
            _UpgradeComposerBar(
                onUpgrade: () => context.push(AppRoutes.premiumPaywall))
          else
            _Composer(
              controller: _textController,
              onSend: _send,
              onAttach: _attach,
              onRequestContact: _requestContact,
              contactAlreadyShared: conversation?.contactShared ?? false,
              replyTarget: replyTarget,
              partnerName: partnerName,
              onCancelReply: () => ref
                  .read(replyTargetProvider(widget.conversationId).notifier)
                  .state = null,
            ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Replaces the message composer when either side has blocked the other.
/// The conversation's direction isn't known here (the list endpoint only
/// reports a combined flag, to avoid leaking who blocked whom) — one
/// neutral message covers both cases.
class _BlockedComposerBar extends StatelessWidget {
  const _BlockedComposerBar();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: context.colors.line)),
        ),
        child: Row(
          children: [
            Icon(Icons.block_rounded, color: context.colors.danger),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('You can no longer message each other.',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Replaces the message composer for free members — reading history and
/// everything else in the chat screen stays fully usable, only sending a
/// new text message is gated behind premium.
class _UpgradeComposerBar extends StatelessWidget {
  final VoidCallback onUpgrade;
  const _UpgradeComposerBar({required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.accentSoft,
          border: Border(top: BorderSide(color: context.colors.line)),
        ),
        child: Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: context.colors.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Upgrade to Premium to send messages.',
                style: context.textStyles.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: onUpgrade,
              child: const Text('Upgrade'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends ConsumerStatefulWidget {
  final ChatMessage message;
  final String conversationId;
  final String partnerName;
  final VoidCallback onReply;
  const _MessageBubble({
    required this.message,
    required this.conversationId,
    required this.partnerName,
    required this.onReply,
  });

  @override
  ConsumerState<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<_MessageBubble>
    with SingleTickerProviderStateMixin {
  bool _busy = false;

  // WhatsApp-style swipe-to-reply. A GestureDetector (not Dismissible) is
  // used here because the gesture never actually dismisses anything — the
  // bubble always returns to x=0, whether the swipe crossed the reply
  // threshold or not, so Dismissible's confirmDismiss-always-false trick
  // would just be fighting Dismissible's own dismiss/resize machinery for
  // no benefit. onHorizontalDragUpdate tracks the raw drag delta, but the
  // bubble's visual offset is a *resisted* function of it (see
  // _resistedOffset) so it decelerates rather than tracking 1:1, and an
  // AnimationController drives the snap-back on release so the bubble
  // eases back to 0 instead of jumping.
  late final AnimationController _snapController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Animation<double>? _snapAnimation;

  double _dragExtent = 0; // raw, unresisted cumulative drag distance
  double _offset = 0; // resisted offset actually applied to the bubble
  bool _triggered = false;

  static const double _maxOffset = 72;
  static const double _triggerThreshold = 44;

  // Only messages from the peer swipe left-to-right and vice versa in real
  // WhatsApp, but this app's bubbles can be swiped either horizontal
  // direction — simpler and still reads fine since the reply icon fades in
  // on whichever side the drag reveals.
  double _resistedOffset(double dragExtent) {
    final direction = dragExtent.sign;
    final magnitude = dragExtent.abs();
    // Rubber-band curve: approaches _maxOffset asymptotically rather than
    // clamping hard, so the last bit of drag still feels alive instead of
    // hitting a wall.
    final resisted = _maxOffset * (1 - (1 / ((magnitude / _maxOffset) + 1)));
    return direction * resisted;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragExtent += details.delta.dx;
      _offset = _resistedOffset(_dragExtent);
      final crossedThreshold = _offset.abs() >= _triggerThreshold;
      if (crossedThreshold && !_triggered) {
        _triggered = true;
        HapticFeedback.selectionClick();
      } else if (!crossedThreshold) {
        _triggered = false;
      }
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_triggered) widget.onReply();
    _snapBack();
  }

  void _snapBack() {
    _snapAnimation = Tween<double>(begin: _offset, end: 0).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOut),
    )..addListener(() => setState(() => _offset = _snapAnimation!.value));
    _snapController
      ..reset()
      ..forward();
    _dragExtent = 0;
    _triggered = false;
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    final failure = await ref
        .read(messagesControllerProvider(widget.conversationId).notifier)
        .respondContactRequest(widget.message.id, accept: accept);
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
    final message = widget.message;

    if (message.kind == MessageKind.system) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Text(message.text,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.colors.muted)),
        ),
      );
    }

    final isSpecial = message.kind != MessageKind.text;
    // A request is only actionable for the recipient, and only while it's
    // still pending — once it resolves, the bubble's text/icon changes to
    // reflect the outcome instead.
    final awaitingMyResponse =
        message.kind == MessageKind.contactRequest && !message.fromMe;

    final (icon, label) = switch (message.kind) {
      MessageKind.contactRequest => (
          Icons.phone_forwarded_outlined,
          message.text
        ),
      MessageKind.contactAccepted => (
          Icons.check_circle_outline_rounded,
          message.fromMe
              ? 'You accepted the contact request.'
              : 'Contact request accepted.'
        ),
      MessageKind.contactDeclined => (
          Icons.cancel_outlined,
          message.fromMe
              ? "You declined this member's contact request."
              : 'This member declined your contact request.'
        ),
      MessageKind.contactShared => (Icons.phone_rounded, message.text),
      MessageKind.document => (Icons.description_outlined, message.text),
      _ => (null, message.text),
    };

    final replyTo = message.replyTo;
    // Only text/special messages get the swipe-to-reply affordance and a
    // reply icon — a swipeable system bubble wouldn't make sense (handled
    // by the early return above), and every remaining kind here is a real
    // message row that can be replied to.
    final revealProgress = (_offset.abs() / _triggerThreshold).clamp(0.0, 1.0);

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      decoration: BoxDecoration(
        color: message.fromMe ? context.colors.accent : context.colors.surface,
        border: message.fromMe ? null : Border.all(color: context.colors.line),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(message.fromMe ? 14 : 2),
          bottomRight: Radius.circular(message.fromMe ? 2 : 14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyTo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: (message.fromMe ? Colors.white : context.colors.accent)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border(
                  left: BorderSide(
                    color:
                        message.fromMe ? Colors.white : context.colors.accent,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // conversationId is the partner's *user* ID — a
                    // reply's quoted sender is "them" if it matches that,
                    // "You" otherwise (the only other possibility, since a
                    // reply can only quote one of the two participants).
                    replyTo.senderUserId == widget.conversationId
                        ? widget.partnerName
                        : 'You',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color:
                          message.fromMe ? Colors.white : context.colors.accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    replyTo.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          (message.fromMe ? Colors.white : context.colors.ink)
                              .withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          if (message.kind == MessageKind.image && message.attachmentUrl != null)
            GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  insetPadding: const EdgeInsets.all(AppSpacing.md),
                  child: InteractiveViewer(
                    child: Image.network(message.attachmentUrl!, fit: BoxFit.contain),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240, minWidth: 160),
                  child: Image.network(
                    message.attachmentUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) => progress == null
                        ? child
                        : const SizedBox(
                            height: 120,
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                    errorBuilder: (context, error, stack) => const SizedBox(
                      height: 120,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                ),
              ),
            )
          else if (message.kind == MessageKind.document && message.attachmentUrl != null)
            InkWell(
              onTap: () => launchUrlString(message.attachmentUrl!),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 20,
                      color: message.fromMe ? Colors.white : context.colors.accent),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: message.fromMe ? Colors.white : context.colors.ink,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (isSpecial)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon,
                        size: 14,
                        color: message.fromMe
                            ? Colors.white
                            : context.colors.accent),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            Text(
              label,
              style: TextStyle(
                color: message.fromMe ? Colors.white : context.colors.ink,
                fontWeight: isSpecial ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
          if (awaitingMyResponse) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _respond(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : () => _respond(true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Accept'),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _snapBack,
      child: Stack(
        alignment:
            message.fromMe ? Alignment.centerRight : Alignment.centerLeft,
        children: [
          if (_offset != 0)
            Positioned(
              left: _offset > 0 ? 0 : null,
              right: _offset < 0 ? 0 : null,
              child: Opacity(
                opacity: revealProgress,
                child: Icon(Icons.reply_rounded,
                    color: context.colors.muted, size: 20),
              ),
            ),
          Transform.translate(
            offset: Offset(_offset, 0),
            child: Align(
              alignment:
                  message.fromMe ? Alignment.centerRight : Alignment.centerLeft,
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends ConsumerWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onRequestContact;
  final bool contactAlreadyShared;
  final ChatMessage? replyTarget;
  final String partnerName;
  final VoidCallback onCancelReply;

  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.onRequestContact,
    required this.contactAlreadyShared,
    required this.replyTarget,
    required this.partnerName,
    required this.onCancelReply,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: context.colors.line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyTarget != null)
              _ReplyPreviewBar(
                message: replyTarget!,
                partnerName: partnerName,
                onCancel: onCancelReply,
              ),
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.attach_file_rounded, color: context.colors.muted),
                  tooltip: 'Attach photo or document',
                  onPressed: onAttach,
                ),
                IconButton(
                  icon: Icon(
                    Icons.contact_phone_outlined,
                    color: contactAlreadyShared
                        ? context.colors.muted
                        : context.colors.accent,
                  ),
                  tooltip: contactAlreadyShared
                      ? 'Contact number already shared'
                      : 'Request contact number',
                  onPressed: contactAlreadyShared ? null : onRequestContact,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Type a message',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send_rounded, color: context.colors.accent),
                  onPressed: onSend,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact quote-style preview shown above the composer while a reply is
/// pending — mirrors the quoted block rendered inside a reply bubble
/// itself, but neutral-toned since it isn't tied to a bubble's own color.
class _ReplyPreviewBar extends StatelessWidget {
  final ChatMessage message;
  final String partnerName;
  final VoidCallback onCancel;

  const _ReplyPreviewBar({
    required this.message,
    required this.partnerName,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.accentSoft,
        borderRadius: BorderRadius.circular(8),
        border:
            Border(left: BorderSide(color: context.colors.accent, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.fromMe ? 'You' : partnerName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.colors.accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.colors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded,
                size: 18, color: context.colors.muted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}
