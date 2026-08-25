import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../shared/models/chat_message.dart';
import '../../../../shared/models/conversation.dart';
import '../../data/api_chat_repository.dart';
import '../../data/chat_socket_service.dart';
import '../../domain/chat_repository.dart';

final conversationsProvider = FutureProvider.autoDispose<List<Conversation>>((ref) async {
  final result = await ref.watch(chatRepositoryProvider).getConversations();
  return result.when(success: (data) => data, failure: (f) => throw f);
});

final unreadConversationCountProvider = Provider.autoDispose<int>((ref) {
  final conversations = ref.watch(conversationsProvider).valueOrNull ?? const [];
  return conversations.where((c) => c.unreadCount > 0).length;
});

/// True once a chat conversation exists for this profile (i.e. an
/// interest was accepted in either direction) — used by profile detail
/// to decide whether the Chat button opens a real conversation.
final conversationForProfileProvider = Provider.autoDispose.family<Conversation?, String>((ref, profileId) {
  final conversations = ref.watch(conversationsProvider).valueOrNull ?? const [];
  for (final c in conversations) {
    if (c.withProfile.id == profileId) return c;
  }
  return null;
});

/// Watched by the chat list screen to keep it live: any incoming "message"
/// event over the WebSocket invalidates the conversations list so unread
/// counts / last-message previews refresh without polling.
final chatLiveUpdatesProvider = Provider.autoDispose<void>((ref) {
  final subscription = ref.watch(chatSocketServiceProvider).events.listen((event) {
    if (event['type'] == 'message') {
      ref.invalidate(conversationsProvider);
    }
  });
  ref.onDispose(subscription.cancel);
});

class MessagesController extends StateNotifier<List<ChatMessage>> {
  final ChatRepository _repository;
  final ChatSocketService _socket;
  final Ref _ref;
  final String conversationId;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _markReadDebounce;

  // ValueNotifiers, not plain mutable bools: a StateNotifier only tells
  // Riverpod watchers about a change when its own `state` is reassigned
  // (here, `state` IS the message list) — a bare `bool` field set
  // directly, as these were, never triggers a rebuild in anything
  // watching this controller, so a "sending…" spinner wired up against
  // them would silently never appear. Wrapping each in its own
  // ValueNotifier makes them independently, correctly watchable (via
  // ValueListenableBuilder or ref.watch(...).addListener) without
  // changing what `state` itself means.
  final sending = ValueNotifier<bool>(false);
  final sendingAttachment = ValueNotifier<bool>(false);
  final requestingContact = ValueNotifier<bool>(false);

  MessagesController(this._repository, this._socket, this._ref, this.conversationId)
      : super(const []) {
    _load();
    _subscription = _socket.events.listen(_onEvent);
  }

  Future<void> _load() async {
    final result = await _repository.getMessages(conversationId);
    result.when(success: (data) => state = data, failure: (_) {});
    // GetHistory marks every unread message from this partner as read
    // server-side — refresh the conversations list so the Inbox/Chat tab
    // badge count drops immediately instead of staying stale until
    // something else happens to invalidate it (previously nothing did,
    // so a "seen" conversation kept showing its old unread count until
    // the next incoming message forced a refresh).
    _ref.invalidate(conversationsProvider);
  }

  /// Live push from the WebSocket — the backend echoes a sent message back
  /// to both sender and receiver, so this also covers the message we just
  /// sent via REST; [_appendIfNew] dedupes it against the optimistic add
  /// from [send].
  void _onEvent(Map<String, dynamic> event) {
    final data = event['data'] as Map<String, dynamic>?;
    if (data == null) return;
    final senderId = data['sender_user_id'] as String?;
    final receiverId = data['receiver_user_id'] as String?;
    if (senderId != conversationId && receiverId != conversationId) return;
    final fromPeer = senderId == conversationId;

    if (event['type'] == 'message_updated') {
      // A contact-request bubble resolving (pending -> accepted/declined)
      // in place, pushed to both sides — update it in-place rather than
      // appending a duplicate.
      _replace(_messageFromJson(data, fromPeer));
      return;
    }
    if (event['type'] != 'message') return;

    _appendIfNew(_messageFromJson(data, fromPeer));
    // A message from the peer that arrives while this window is already
    // open is effectively seen immediately — GetHistory marks unread
    // messages read server-side as a side effect (there's no dedicated
    // mark-read endpoint) and its response also refreshes the badge
    // count, so re-running _load() is how that happens. Debounced rather
    // than fired per-message: a burst of several incoming messages used
    // to trigger one full history refetch each, even though the message
    // itself was already appended above — this collapses a rapid burst
    // into a single refetch shortly after it settles.
    if (fromPeer) {
      _markReadDebounce?.cancel();
      _markReadDebounce = Timer(const Duration(milliseconds: 800), _load);
    }
  }

  ChatMessage _messageFromJson(Map<String, dynamic> data, bool fromPeer) {
    final replyToJson = data['reply_to'] as Map<String, dynamic>?;
    return ChatMessage(
      id: data['id'] as String,
      text: data['body'] as String,
      fromMe: !fromPeer,
      timestamp: DateTime.parse(data['created_at'] as String),
      kind: _kindFromBackend(data['kind'] as String?),
      replyTo: replyToJson == null ? null : ReplyToPreview.fromJson(replyToJson),
      attachmentUrl: data['attachment_url'] as String?,
    );
  }

  MessageKind _kindFromBackend(String? kind) {
    switch (kind) {
      case 'contact_request':
        return MessageKind.contactRequest;
      case 'contact_accepted':
        return MessageKind.contactAccepted;
      case 'contact_declined':
        return MessageKind.contactDeclined;
      case 'contact_shared':
        return MessageKind.contactShared;
      case 'image':
        return MessageKind.image;
      case 'document':
        return MessageKind.document;
      default:
        return MessageKind.text;
    }
  }

  void _appendIfNew(ChatMessage message) {
    if (!mounted || state.any((m) => m.id == message.id)) return;
    state = [...state, message];
  }

  void _replace(ChatMessage message) {
    if (!mounted) return;
    state = [for (final m in state) if (m.id == message.id) message else m];
  }

  /// Returns the failure on error (null on success) so the screen can show
  /// it — silently dropping it here previously made a failed send (e.g.
  /// backend rejection) look identical to a successful one that just never
  /// arrived, with no indication of what went wrong.
  Future<AppFailure?> send(String text, {String? replyToMessageId}) async {
    if (text.trim().isEmpty) return null;
    sending.value = true;
    final result = await _repository.sendMessage(
      conversationId,
      text.trim(),
      replyToMessageId: replyToMessageId,
    );
    sending.value = false;
    AppFailure? failure;
    result.when(success: _appendIfNew, failure: (f) => failure = f);
    return failure;
  }

  Future<AppFailure?> sendAttachment(List<int> bytes, String filename) async {
    sendingAttachment.value = true;
    final result = await _repository.sendAttachment(conversationId, bytes, filename);
    sendingAttachment.value = false;
    AppFailure? failure;
    result.when(success: _appendIfNew, failure: (f) => failure = f);
    return failure;
  }

  Future<AppFailure?> requestContactNumber() async {
    requestingContact.value = true;
    final result = await _repository.requestContactNumber(conversationId);
    requestingContact.value = false;
    AppFailure? failure;
    result.when(success: _appendIfNew, failure: (f) => failure = f);
    return failure;
  }

  /// Accepts or declines a contact request the peer sent us. The resolved
  /// bubble (and, on accept, the follow-up message carrying the number)
  /// also arrive over the socket as `message_updated`/`message` events —
  /// this optimistic update just avoids waiting on that round-trip.
  Future<AppFailure?> respondContactRequest(String messageId, {required bool accept}) async {
    final result = await _repository.respondContactRequest(messageId, accept: accept);
    AppFailure? failure;
    result.when(success: _replace, failure: (f) => failure = f);
    return failure;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _markReadDebounce?.cancel();
    sending.dispose();
    sendingAttachment.dispose();
    requestingContact.dispose();
    super.dispose();
  }
}

final messagesControllerProvider = StateNotifierProvider.autoDispose
    .family<MessagesController, List<ChatMessage>, String>((ref, conversationId) {
  return MessagesController(
    ref.watch(chatRepositoryProvider),
    ref.watch(chatSocketServiceProvider),
    ref,
    conversationId,
  );
});

/// The message currently being replied to in a given conversation's
/// composer — set by swiping a bubble, cleared on send or explicit
/// cancel. Kept separate from [messagesControllerProvider]'s state (the
/// message list itself) since it's purely local UI state, not something
/// fetched from or echoed by the backend.
final replyTargetProvider =
    StateProvider.autoDispose.family<ChatMessage?, String>((ref, conversationId) => null);
