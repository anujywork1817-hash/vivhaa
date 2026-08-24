import '../../../core/api/api_result.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/conversation.dart';

abstract class ChatRepository {
  Future<ApiResult<List<Conversation>>> getConversations();
  Future<ApiResult<List<ChatMessage>>> getMessages(String conversationId);
  Future<ApiResult<ChatMessage>> sendMessage(String conversationId, String text, {String? replyToMessageId});

  /// Sends a contact-request message to the partner — does not reveal
  /// anything by itself. The partner must accept or decline via
  /// [respondContactRequest]; only an accept ever produces the real
  /// number, delivered as a follow-up message.
  Future<ApiResult<ChatMessage>> requestContactNumber(String conversationId);

  /// Accepts or declines a pending contact request. [messageId] is the id
  /// of the contact-request message itself (the backend mutates that same
  /// row in place rather than tracking requests separately).
  Future<ApiResult<ChatMessage>> respondContactRequest(String messageId, {required bool accept});

  /// Uploads [bytes] (an image from gallery/camera, or a document — PDF/
  /// Word) as a new message. [filename] drives both content-type
  /// detection and, for a non-image file, the caption shown in the
  /// bubble/notification.
  Future<ApiResult<ChatMessage>> sendAttachment(
    String conversationId,
    List<int> bytes,
    String filename,
  );
}
