import '../core/network/envelope.dart';

/// One audit row from `GET /api/fm/history/{Type}/{id}`.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.action,
    required this.description,
    required this.userName,
    this.performedByRole,
    this.fieldName,
    this.oldValue,
    this.newValue,
    this.timestamp,
  });

  final String id;
  final String action;
  final String description;
  final String userName;
  final String? performedByRole;
  final String? fieldName;
  final String? oldValue;
  final String? newValue;
  final DateTime? timestamp;

  bool get hasValueChange =>
      (oldValue?.isNotEmpty ?? false) || (newValue?.isNotEmpty ?? false);

  /// `STATUS_UPDATE` reads as "Status Update".
  String get actionLabel => action
      .split('_')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join(' ');

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id']?.toString() ?? '',
        action: json['action']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        userName: firstNonEmpty([json['userName']]) ?? 'Unknown',
        performedByRole: json['performedByRole']?.toString(),
        fieldName: json['fieldName']?.toString(),
        oldValue: json['oldValue']?.toString(),
        newValue: json['newValue']?.toString(),
        timestamp: asDate(json['timestamp'] ?? json['createdAt']),
      );
}
