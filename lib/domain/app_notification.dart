import '../core/network/envelope.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.category,
    this.entityId,
    this.entityType,
    this.link,
    this.isSeen = false,
    this.isRead = false,
    this.createdAt,
  });

  final String id;
  final String title;
  final String message;

  /// info | warning | success | error
  final String type;
  final String? category;
  final String? entityId;
  final String? entityType;
  final String? link;

  /// Seen means the bell was opened after it arrived; read means this one was
  /// opened. The badge counts unseen.
  final bool isSeen;
  final bool isRead;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        type: json['type']?.toString() ?? 'info',
        category: json['category']?.toString(),
        entityId: json['entityId']?.toString(),
        entityType: json['entityType']?.toString(),
        link: json['link']?.toString(),
        isSeen: asBool(json['isSeen']) ?? false,
        isRead: asBool(json['isRead']) ?? false,
        createdAt: asDate(json['createdAt']),
      );
}
