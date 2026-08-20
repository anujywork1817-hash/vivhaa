import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/chat_message.dart';
import '../../../../shared/models/conversation.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../../../calls/presentation/controllers/call_controller.dart';
import '../../../calls/presentation/screens/active_call_screen.dart';
import '../../../profile_detail/presentation/widgets/profile_actions_sheet.dart';
import '../controllers/chat_controller.dart';

class ChatWindowScreen extends ConsumerStatefulWidget {
  final String conversationId;
  const ChatWindowScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatWindowScreen> createState() => _ChatWindowScreenState();
}

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
    _textController.clear();
    final failure =
        await ref.read(messagesControllerProvider(widget.conversationId).notifier).send(text);
    if (failure != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
    }
    _scrollToBottom();
  }

  Future<void> _startCall(Conversation conversation, {bool isVideo = true}) async {
    if (ref.read(callControllerProvider).isActive) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("You're already on a call.")));
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

  Future<void> _requestContact() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request contact number?'),
        content: const Text("They'll see that you'd like to continue the conversation over phone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Request')),
        ],
      ),
    );
    if (confirmed != true) return;
    final failure = await ref
        .read(messagesControllerProvider(widget.conversationId).notifier)
        .requestContactNumber();
    if (failure != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
    }
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ref.watch(conversationsProvider).valueOrNull
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final messages = ref.watch(messagesControllerProvider(widget.conversationId));

    ref.listen(messagesControllerProvider(widget.conversationId), (_, __) => _scrollToBottom());

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
                        style: context.textStyles.titleMedium, overflow: TextOverflow.ellipsis),
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
              ),
            ),
          ),
          if (conversation?.isBlocked ?? false)
            const _BlockedComposerBar()
          else
            _Composer(
              controller: _textController,
              onSend: _send,
              onRequestContact: _requestContact,
              contactAlreadyShared: conversation?.contactShared ?? false,
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
                  style: context.textStyles.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
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
  const _MessageBubble({required this.message, required this.conversationId});

  @override
  ConsumerState<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<_MessageBubble> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    final failure = await ref
        .read(messagesControllerProvider(widget.conversationId).notifier)
        .respondContactRequest(widget.message.id, accept: accept);
    if (!mounted) return;
    setState(() => _busy = false);
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
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
              style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
        ),
      );
    }

    final isSpecial = message.kind != MessageKind.text;
    // A request is only actionable for the recipient, and only while it's
    // still pending — once it resolves, the bubble's text/icon changes to
    // reflect the outcome instead.
    final awaitingMyResponse = message.kind == MessageKind.contactRequest && !message.fromMe;

    final (icon, label) = switch (message.kind) {
      MessageKind.contactRequest => (Icons.phone_forwarded_outlined, message.text),
      MessageKind.contactAccepted => (
          Icons.check_circle_outline_rounded,
          message.fromMe ? 'You accepted the contact request.' : 'Contact request accepted.'
        ),
      MessageKind.contactDeclined => (
          Icons.cancel_outlined,
          message.fromMe
              ? "You declined this member's contact request."
              : 'This member declined your contact request.'
        ),
      MessageKind.contactShared => (Icons.phone_rounded, message.text),
      _ => (null, message.text),
    };

    return Align(
      alignment: message.fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
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
            if (isSpecial)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 14, color: message.fromMe ? Colors.white : context.colors.accent),
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
      ),
    );
  }
}

class _Composer extends ConsumerWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onRequestContact;
  final bool contactAlreadyShared;

  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onRequestContact,
    required this.contactAlreadyShared,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: context.colors.line)),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.contact_phone_outlined,
                color: contactAlreadyShared ? context.colors.muted : context.colors.accent,
              ),
              tooltip: contactAlreadyShared ? 'Contact number already shared' : 'Request contact number',
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
      ),
    );
  }
}
