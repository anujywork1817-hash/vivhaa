import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/ai_message.dart';
import '../controllers/ai_assistant_controller.dart';

/// AI-powered help & support — doubles as the app's "Help & Support" menu
/// item and a general AI matchmaking assistant (profile tips, conversation
/// starters). Backed by Groq on the backend; if no API key is configured
/// there, every send fails with a clear message rather than pretending to
/// answer.
class AiAssistantScreen extends ConsumerStatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
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
    await ref.read(aiAssistantControllerProvider.notifier).send(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiAssistantControllerProvider);
    ref.listen(aiAssistantControllerProvider, (_, __) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(title: const Text('AI Assistant')),
      body: Column(
        children: [
          if (state.failure != null)
            Container(
              width: double.infinity,
              color: context.colors.danger.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text(state.failure!.message,
                  style: context.textStyles.bodySmall?.copyWith(color: context.colors.danger)),
            ),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            'Ask me for profile tips, conversation starters, or how to use Vivah.',
                            textAlign: TextAlign.center,
                            style: context.textStyles.bodyMedium
                                ?.copyWith(color: context.colors.muted),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: state.messages.length,
                        itemBuilder: (context, i) => _Bubble(message: state.messages[i]),
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: context.colors.surface,
                border: Border(top: BorderSide(color: context.colors.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Ask the AI assistant…',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  state.sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          icon: Icon(Icons.send_rounded, color: context.colors.accent),
                          onPressed: _send,
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final AiMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final fromMe = message.role == AiMessageRole.user;
    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: fromMe ? context.colors.accent : context.colors.surface,
          border: fromMe ? null : Border.all(color: context.colors.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(fromMe ? 14 : 2),
            bottomRight: Radius.circular(fromMe ? 2 : 14),
          ),
        ),
        child: Text(
          message.content,
          style: TextStyle(color: fromMe ? Colors.white : context.colors.ink),
        ),
      ),
    );
  }
}
