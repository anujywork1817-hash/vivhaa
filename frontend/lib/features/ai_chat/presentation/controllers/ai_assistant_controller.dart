import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../shared/models/ai_message.dart';
import '../../data/api_ai_repository.dart';
import '../../domain/ai_repository.dart';

class AiAssistantState {
  final List<AiMessage> messages;
  final bool loading;
  final bool sending;
  final AppFailure? failure;

  const AiAssistantState({
    this.messages = const [],
    this.loading = true,
    this.sending = false,
    this.failure,
  });

  AiAssistantState copyWith({
    List<AiMessage>? messages,
    bool? loading,
    bool? sending,
    AppFailure? failure,
    bool clearFailure = false,
  }) {
    return AiAssistantState(
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
      sending: sending ?? this.sending,
      failure: clearFailure ? null : failure ?? this.failure,
    );
  }
}

class AiAssistantController extends StateNotifier<AiAssistantState> {
  final AiRepository _repository;

  AiAssistantController(this._repository) : super(const AiAssistantState()) {
    _load();
  }

  Future<void> _load() async {
    final result = await _repository.getHistory();
    result.when(
      success: (data) => state = state.copyWith(messages: data, loading: false),
      failure: (f) => state = state.copyWith(loading: false, failure: f),
    );
  }

  Future<void> send(String text) async {
    if (text.trim().isEmpty || state.sending) return;
    state = state.copyWith(sending: true, clearFailure: true);
    final result = await _repository.sendMessage(text.trim());
    result.when(
      success: (reply) {
        // The backend persists both the user's message and the reply —
        // append both locally rather than re-fetching the whole history.
        final userMessage = AiMessage(
          id: '${reply.id}-user',
          role: AiMessageRole.user,
          content: text.trim(),
          timestamp: DateTime.now(),
        );
        state = state.copyWith(
          messages: [...state.messages, userMessage, reply],
          sending: false,
        );
      },
      failure: (f) => state = state.copyWith(sending: false, failure: f),
    );
  }
}

final aiAssistantControllerProvider =
    StateNotifierProvider.autoDispose<AiAssistantController, AiAssistantState>((ref) {
  return AiAssistantController(ref.watch(aiRepositoryProvider));
});
