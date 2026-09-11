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
    this.view = ChatSheetView.home,
    this.mode = ChatMode.general,
    this.messages = const [],
    this.loadingHistory = false,
    this.sending = false,
    this.pastView = ChatMode.general,
    this.pastMessages = const [],
  });

  /// Which panel is showing — see [ChatSheetView].
  final ChatSheetView view;

  /// Which server behavior [ChatController.send] runs the next message
  /// through when [view] is [ChatSheetView.chat].
  final ChatMode mode;

  /// This visit's own thread only — cleared every time [ChatController.
  /// openMode] runs, so the panel always opens on a clean screen even though
  /// the underlying server-side session is the same one every time (see
  /// [AiChatRepository.sessionIdFor]). Past turns are reachable only through
  /// [pastMessages], not by reloading them in here.
  final List<ChatMessage> messages;

  final bool loadingHistory;
  final bool sending;

  /// Which mode's thread [pastMessages] holds, while [view] is
  /// [ChatSheetView.historyDetail].
  final ChatMode pastView;
  final List<ChatMessage> pastMessages;

  ChatState copyWith({
    ChatSheetView? view,
    ChatMode? mode,
    List<ChatMessage>? messages,
    bool? loadingHistory,
    bool? sending,
    ChatMode? pastView,
    List<ChatMessage>? pastMessages,
  }) =>
      ChatState(
        view: view ?? this.view,
        mode: mode ?? this.mode,
        messages: messages ?? this.messages,
        loadingHistory: loadingHistory ?? this.loadingHistory,
        sending: sending ?? this.sending,
        pastView: pastView ?? this.pastView,
        pastMessages: pastMessages ?? this.pastMessages,
      );
}

/// The assistant sheet for one order — three server-side threads (general
/// checklist Q&A, asset request, asset report; see [ChatMode]), each
/// deterministic per order so it survives across sheet opens, but the sheet
/// itself always opens on [ChatSheetView.home] with an empty [ChatState.
/// messages]: mirrors the web facility agent's own "always a fresh screen,
/// past turns are one tap away" shape (facility-ai-agent.tsx) rather than
/// dumping the full thread back into view on every open.
class ChatController extends FamilyNotifier<ChatState, OrderKey> {
  var _contextBuilt = false;

  @override
  ChatState build(OrderKey arg) => const ChatState();

  AiChatRepository get _repository => ref.read(aiChatRepositoryProvider);

  String _sessionIdFor(ChatMode mode) =>
      AiChatRepository.sessionIdFor(arg.type, arg.id, mode: mode);

  /// Fire and forget: the server caches this order so the first question
  /// already has the checklist and asset to hand. Safe to call every time the
  /// sheet opens — cheap, and idempotent server-side.
  void open() {
    if (_contextBuilt) return;
    _contextBuilt = true;
    unawaited(_repository.buildContext(arg.type, arg.id));
  }

  /// Home tile tapped — always starts the visible thread empty, whether or
  /// not this mode's server-side session already has turns in it.
  void openMode(ChatMode mode) {
    if (state.sending) return;
    state = state.copyWith(view: ChatSheetView.chat, mode: mode, messages: const []);
  }

  void goHome() {
    if (state.sending) return;
    state = state.copyWith(view: ChatSheetView.home);
  }

  void openHistoryList() {
    if (state.sending) return;
    state = state.copyWith(view: ChatSheetView.historyList);
  }

  /// Loads the given mode's thread read-only. Always re-fetches — this is a
  /// "look back", not a cache, and the thread may have grown since it was
  /// last opened.
  Future<void> openHistoryThread(ChatMode mode) async {
    state = state.copyWith(
      view: ChatSheetView.historyDetail,
      pastView: mode,
      pastMessages: const [],
      loadingHistory: true,
    );
    try {
      final messages = await _repository.history(_sessionIdFor(mode));
      // The user may have already tapped back to a different thread by the
      // time this resolves — only apply it if it's still the one showing.
      if (state.view == ChatSheetView.historyDetail && state.pastView == mode) {
        state = state.copyWith(pastMessages: messages, loadingHistory: false);
      }
    } catch (_) {
      if (state.view == ChatSheetView.historyDetail && state.pastView == mode) {
        state = state.copyWith(loadingHistory: false);
      }
    }
  }

  Future<void> send(
    String text, {
    List<String> images = const [],
    String? audio,
  }) async {
    final message = text.trim();
    // Empty text is fine as long as there's an image or a voice note — the
    // server transcribes/reads the attachment itself (see
    // technicianChecklistAiController.ts). Only block when there is
    // genuinely nothing to send.
    final hasContent = message.isNotEmpty || images.isNotEmpty || audio != null;
    if (!hasContent || state.sending || state.view != ChatSheetView.chat) return;

    final question = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      content: message,
      fromTechnician: true,
      sentAt: DateTime.now(),
      images: images,
      audio: audio,
    );
    final placeholder = ChatMessage(
      id: 'pending-${question.id}',
      content: '',
      fromTechnician: false,
      sentAt: DateTime.now(),
      pending: true,
    );

    final mode = state.mode;
    state = state.copyWith(
      messages: [...state.messages, question, placeholder],
      sending: true,
    );

    try {
      final reply = await _repository.send(
        message: message,
        sessionId: _sessionIdFor(mode),
        type: arg.type,
        recordId: arg.id,
        mode: mode,
        images: images,
        audio: audio,
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
