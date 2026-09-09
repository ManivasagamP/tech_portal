import '../core/network/api_client.dart';
import '../domain/chat_message.dart';
import '../domain/maintenance_record.dart';

/// The per-order assistant. Online only, and deliberately so: an answer
/// composed from a stale cached order would be worse than no answer.
class AiChatRepository {
  AiChatRepository(this._api);

  final ApiClient _api;

  /// The thread id the server keys history on. Deterministic per order, so
  /// reopening a job resumes the same conversation instead of starting over —
  /// and the `technician-checklist:` prefix keeps it out of the general
  /// facility agent's history.
  static String sessionIdFor(OrderType type, String recordId) =>
      'technician-checklist:${type.slug}:$recordId';

  Future<List<ChatMessage>> history(String sessionId) async {
    final response = await _api.get(
      '/api/fm/ai/chat/history',
      query: {'page': 1, 'limit': 200, 'sessionId': sessionId},
    );
    // This endpoint answers with a bare `{messages, pagination}` — no data
    // envelope — so it is read directly rather than through unwrapList.
    final body = response.data;
    final rows = body is Map ? body['messages'] : null;
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => ChatMessage.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Returns the assistant's reply text and the id it was stored under.
  ///
  /// [images] are `data:<mimeType>;base64,<data>` strings (see
  /// `CapturedPhoto.dataUrl`) — the exact shape the controller destructures
  /// straight from `req.body.images` and forwards into `runFacilityAgentTurn`,
  /// which regex-parses that format into Gemini `inlineData` parts. No other
  /// encoding or upload step is needed. [audio] is the same shape but
  /// singular (see `VoiceRecording.dataUrl`) — one voice note per message.
  Future<({String content, String? messageId})> send({
    required String message,
    required String sessionId,
    required OrderType type,
    required String recordId,
    List<String> images = const [],
    String? audio,
  }) async {
    final response = await _api.post(
      '/api/fm/ai/technician-checklist/chat',
      data: {
        'message': message,
        'sessionId': sessionId,
        'maintenanceId': recordId,
        // The endpoint validates this against its own vocabulary, which is the
        // same slug set the detail routes use.
        'maintenanceType': type.slug,
        if (images.isNotEmpty) 'images': images,
        'audio': ?audio,
      },
      // Model turns are slow; the default 30 s read timeout cuts them off.
      receiveTimeout: const Duration(seconds: 90),
    );
    final body = response.data;
    return (
      content: body is Map
          ? (body['content']?.toString() ?? 'No response from the assistant.')
          : 'No response from the assistant.',
      messageId: body is Map ? body['messageId']?.toString() : null,
    );
  }

  /// Tells the server to cache the order the technician is looking at, so the
  /// first question already has context. Fire and forget — the chat works
  /// without it, and its failure must never surface.
  Future<void> buildContext(OrderType type, String recordId) async {
    try {
      await _api.post(
        '/api/fm/ai/context/build',
        data: {
          'route': '/technician/orders/${type.slug}/$recordId',
          'params': {'id': recordId},
        },
      );
    } catch (_) {
      // Intentionally silent.
    }
  }
}
