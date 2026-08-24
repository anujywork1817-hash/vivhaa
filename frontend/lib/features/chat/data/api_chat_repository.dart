import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/conversation.dart';
import '../../../shared/models/match_profile.dart';
import '../domain/chat_repository.dart';

/// Talks to the real matrimony_backend `/chat/*` REST endpoints (message
/// send/receive over `/ws/chat` is handled separately by
/// [ChatSocketService] — this repository only covers request/response
/// calls).
///
/// The backend identifies a conversation by the partner's *user* ID, but
/// the rest of the app (profile actions, navigation) works in *profile*
/// IDs. Chat is only reachable once an interest is mutually accepted, so
/// every partner is guaranteed to have an accepted interest on record —
/// this repository reads `/interests/sent` and `/interests/received` to
/// build the user-ID -> profile-ID mapping conversations need.
class ApiChatRepository implements ChatRepository {
  final ApiClient _client;

  ApiChatRepository(this._client);

  @override
  Future<ApiResult<List<Conversation>>> getConversations() async {
    try {
      final profileIdByUserId = await _resolveProfileIds();
      final response = await _client.dio.get(ApiEndpoints.conversations);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      final conversations = rows.map((json) {
        final partnerUserId = json['partner_user_id'] as String;
        return Conversation(
          id: partnerUserId,
          withProfile: MatchProfile(
            id: profileIdByUserId[partnerUserId] ?? partnerUserId,
            name: (json['partner_name'] as String?) ?? 'Member',
            age: 0,
            heightCm: 0,
            city: '',
            profession: '',
            education: '',
            religion: '',
            photoSeed: json['partner_photo_url'] as String?,
          ),
          lastMessage: json['last_message'] as String,
          lastMessageAt: DateTime.parse(json['last_message_at'] as String),
          unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
          isBlocked: json['is_blocked'] as bool? ?? false,
        );
      }).toList();
      return ApiResult.success(conversations);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<List<ChatMessage>>> getMessages(String conversationId) async {
    try {
      final response = await _client.dio.get(ApiEndpoints.messages(conversationId));
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map((json) => _fromJson(json, conversationId)).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<ChatMessage>> sendMessage(String conversationId, String text, {String? replyToMessageId}) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.messages(conversationId),
        data: {
          'body': text,
          if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
        },
      );
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(_fromJson(data, conversationId));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<ChatMessage>> requestContactNumber(String conversationId) async {
    try {
      final response = await _client.dio.post(ApiEndpoints.requestContact(conversationId));
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(_fromJson(data, conversationId));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<ChatMessage>> respondContactRequest(String messageId, {required bool accept}) async {
    try {
      final path = accept ? ApiEndpoints.acceptContact(messageId) : ApiEndpoints.declineContact(messageId);
      final response = await _client.dio.post(path);
      final data = response.data['data'] as Map<String, dynamic>;
      // The backend keys fromMe off the *sender*; conversationId isn't
      // known here, so pass the sender itself — a resolved request bubble
      // is rendered the same regardless of direction, so fromMe doesn't
      // affect its display.
      return ApiResult.success(_fromJson(data, data['receiver_user_id'] as String));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<ChatMessage>> sendAttachment(
    String conversationId,
    List<int> bytes,
    String filename,
  ) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.chatAttachment(conversationId),
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            bytes,
            filename: filename,
            // Required — without an explicit content-type dio defaults to
            // application/octet-stream, which the backend's
            // storage.ValidateChatAttachment rejects outright.
            contentType: _attachmentMediaType(filename),
          ),
        }),
      );
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(_fromJson(data, conversationId));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  DioMediaType _attachmentMediaType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return DioMediaType('image', 'png');
    if (lower.endsWith('.webp')) return DioMediaType('image', 'webp');
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return DioMediaType('image', 'jpeg');
    if (lower.endsWith('.pdf')) return DioMediaType('application', 'pdf');
    if (lower.endsWith('.docx')) {
      return DioMediaType(
          'application', 'vnd.openxmlformats-officedocument.wordprocessingml.document');
    }
    if (lower.endsWith('.doc')) return DioMediaType('application', 'msword');
    return DioMediaType('application', 'octet-stream');
  }

  ChatMessage _fromJson(Map<String, dynamic> json, String conversationId) {
    final replyToJson = json['reply_to'] as Map<String, dynamic>?;
    return ChatMessage(
      id: json['id'] as String,
      text: json['body'] as String,
      fromMe: json['sender_user_id'] != conversationId,
      timestamp: DateTime.parse(json['created_at'] as String),
      kind: _kindFromBackend(json['kind'] as String?),
      replyTo: replyToJson == null ? null : ReplyToPreview.fromJson(replyToJson),
      attachmentUrl: json['attachment_url'] as String?,
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

  Future<Map<String, String>> _resolveProfileIds() async {
    final map = <String, String>{};
    try {
      final results = await Future.wait([
        _client.dio.get(ApiEndpoints.interestsSent),
        _client.dio.get(ApiEndpoints.interestsReceived),
      ]);
      for (final response in results) {
        final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
        for (final row in rows) {
          final profileId = row['profile_id'] as String?;
          if (profileId == null || profileId.isEmpty) continue;
          final senderId = row['sender_user_id'] as String;
          final receiverId = row['receiver_user_id'] as String;
          // profile_id is always the *other* party's — record whichever
          // side isn't identifiable as "us" by checking both; harmless to
          // map both since only the partner's ID will ever be looked up.
          map[senderId] = profileId;
          map[receiverId] = profileId;
        }
      }
    } on DioException {
      // Best-effort — conversations still render with a fallback ID.
    }
    return map;
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ApiChatRepository(ref.watch(apiClientProvider));
});
