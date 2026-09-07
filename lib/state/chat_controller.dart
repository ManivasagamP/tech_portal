import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ai_chat_repository.dart';
import '../domain/chat_message.dart';
import 'order_detail_controller.dart';
import 'providers.dart';

final aiChatRepositoryProvider = Provider<AiChatRepository>(
  (ref) => AiChatRepository(ref.watch(apiClientProvider)),
);

class ChatState {
  const ChatState({
    this.messages = const [],
    this.loadingHistory = false,
    this.sending = false,
  });

  final List<ChatMessage> messages;
  final bool loadingHistory;
  final bool sending;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? loadingHistory,
    bool? sending,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        loadingHistory: loadingHistory ?? this.loadingHistory,
        sending: sending ?? this.sending,
      );
}

/// The assistant thread for one order.
///
/// History is fetched the first time the panel opens rather than when the
/// order does — most technicians never open it, and the account has to have
/// the AI permission at all.
class ChatController extends FamilyNotifier<ChatState, OrderKey> {
  late final String _sessionId =
      AiChatRepository.sessionIdFor(arg.type, arg.id);

  var _loaded = false;

  @override
  ChatState build(OrderKey arg) => const ChatState();

  AiChatRepository get _repository => ref.read(aiChatRepositoryProvider);

  Future<void> open() async {
    if (_loaded) return;
    _loaded = true;

    // Fire and forget: the server caches this order so the first question
    // already has the checklist and asset to hand.
    unawaited(_repository.buildContext(arg.type, arg.id));

    state = state.copyWith(loadingHistory: true);
    try {
      final messages = await _repository.history(_sessionId);
      state = ChatState(messages: messages);
    } catch (_) {
      // An unreachable history is not worth blocking on — the thread just
      // starts empty and the greeting takes over.
      state = const ChatState();
    }
  }

  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty || state.sending) return;

    final question = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      content: message,
      fromTechnician: true,
      sentAt: DateTime.now(),
    );
    final placeholder = ChatMessage(
      id: 'pending-${question.id}',
      content: '',
      fromTechnician: false,
      sentAt: DateTime.now(),
      pending: true,
    );

    state = state.copyWith(
      messages: [...state.messages, question, placeholder],
      sending: true,
    );

    try {
      final reply = await _repository.send(
        message: message,
        sessionId: _sessionId,
        type: arg.type,
        recordId: arg.id,
      );
      _replacePlaceholder(placeholder, reply.content, reply.messageId);
    } catch (_) {
      _replacePlaceholder(
        placeholder,
        'That did not go through. Try asking again.',
        null,
      );
    }
  }

  void _replacePlaceholder(ChatMessage placeholder, String text, String? id) {
    state = state.copyWith(
      messages: [
        for (final message in state.messages)
          if (message.id == placeholder.id)
            message.answeredWith(text, id)
          else
            message,
      ],
      sending: false,
    );
  }
}

final chatControllerProvider =
    NotifierProvider.family<ChatController, ChatState, OrderKey>(
  ChatController.new,
);
