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
  });

  final String id;
  final String content;
  final bool fromTechnician;
  final DateTime? sentAt;

  /// A placeholder shown while the answer is being written.
  final bool pending;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
        fromTechnician: json['type']?.toString() == 'user',
        sentAt: asDate(json['timestamp']),
      );

  ChatMessage answeredWith(String text, String? id) => ChatMessage(
        id: id ?? this.id,
        content: text,
        fromTechnician: false,
        sentAt: sentAt,
      );
}
