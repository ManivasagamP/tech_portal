import 'dart:convert';
import 'dart:typed_data';

import '../core/network/envelope.dart';

/// One line in the per-order assistant thread. The server calls the two sides
/// "user" and "agent"; anything else it might add is treated as the agent
/// talking, since that is the safe side to render.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.content,
    required this.fromTechnician,
    this.sentAt,
    this.pending = false,
    this.images = const [],
    this.audio,
  });

  final String id;
  final String content;
  final bool fromTechnician;
  final DateTime? sentAt;

  /// A placeholder shown while the answer is being written.
  final bool pending;

  /// Images the technician attached to this message, as the same
  /// `data:<mime>;base64,<data>` strings sent to and echoed back by
  /// `/api/fm/ai/technician-checklist/chat` — both a fresh send (built from
  /// `CapturedPhoto.dataUrl`) and `/api/fm/ai/chat/history` (which persists
  /// and returns the same array verbatim) shape it identically.
  final List<String> images;

  /// The one voice note attached to this message, if any — same
  /// `data:<mime>;base64,<data>` shape as [images] (see
  /// `VoiceRecording.dataUrl`), but singular: one clip per message, not a
  /// list.
  final String? audio;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
        fromTechnician: json['type']?.toString() == 'user',
        sentAt: asDate(json['timestamp']),
        images: (json['images'] is List)
            ? (json['images'] as List).whereType<String>().toList()
            : const [],
        audio: json['audio']?.toString().isNotEmpty == true
            ? json['audio'].toString()
            : null,
      );

  ChatMessage answeredWith(String text, String? id) => ChatMessage(
        id: id ?? this.id,
        content: text,
        fromTechnician: false,
        sentAt: sentAt,
      );
}

/// Decodes a `data:<mime>;base64,<data>` string back to raw bytes, for
/// rendering a thumbnail of an image attached to a chat message. Returns null
/// for anything that doesn't match — a malformed or unexpected entry should
/// disappear from the thread, not crash it.
Uint8List? decodeChatImage(String dataUrl) {
  final match = RegExp(r'^data:[^;,]+;base64,(.+)$', dotAll: true)
      .firstMatch(dataUrl);
  if (match == null) return null;
  try {
    return base64Decode(match.group(1)!);
  } catch (_) {
    return null;
  }
}
