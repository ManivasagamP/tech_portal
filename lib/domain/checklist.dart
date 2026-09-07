import '../core/network/envelope.dart';

class ChecklistNote {
  const ChecklistNote({
    required this.text,
    this.createdAt,
    this.audioUrl,
    this.durationSeconds,
  });

  final String text;
  final DateTime? createdAt;
  final String? audioUrl;
  final int? durationSeconds;

  factory ChecklistNote.fromJson(Map<String, dynamic> json) => ChecklistNote(
        text: json['text']?.toString() ?? '',
        createdAt: asDate(json['createdAt']),
        audioUrl: json['audioUrl']?.toString(),
        durationSeconds: asInt(json['durationSeconds']),
      );
}

class ChecklistAttachment {
  const ChecklistAttachment({
    required this.url,
    this.name,
    this.createdAt,
    this.type,
  });

  final String url;
  final String? name;
  final DateTime? createdAt;
  final String? type;

  factory ChecklistAttachment.fromJson(Map<String, dynamic> json) =>
      ChecklistAttachment(
        url: json['url']?.toString() ?? '',
        name: json['name']?.toString(),
        createdAt: asDate(json['createdAt']),
        type: json['type']?.toString(),
      );
}

class ChecklistSession {
  const ChecklistSession({
    this.startTime,
    this.endTime,
    this.timeSpent,
    this.faceCaptureUrl,
    this.endFaceCaptureUrl,
    this.city,
    this.district,
    this.latitude,
    this.longitude,
    this.ipAddress,
  });

  final DateTime? startTime;
  final DateTime? endTime;

  /// Minutes, as the server stores them.
  final int? timeSpent;
  final String? faceCaptureUrl;
  final String? endFaceCaptureUrl;
  final String? city;
  final String? district;
  final double? latitude;
  final double? longitude;
  final String? ipAddress;

  bool get isRunning => endTime == null;

  /// "Sarcarsamakulam, Tamil Nadu", or null on the sessions recorded before
  /// the app resolved names — those still have their coordinates to show.
  String? get placeLabel {
    final parts = [city, district].where((p) => p != null && p.isNotEmpty);
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Older rows nest the geo fields under `location` instead of inlining them.
  factory ChecklistSession.fromJson(Map<String, dynamic> json) {
    final nested = json['location'];
    final geo = nested is Map ? Map<String, dynamic>.from(nested) : const {};
    return ChecklistSession(
      startTime: asDate(json['startTime']),
      endTime: asDate(json['endTime']),
      timeSpent: asInt(json['timeSpent']),
      faceCaptureUrl: json['faceCaptureUrl']?.toString(),
      endFaceCaptureUrl: json['endFaceCaptureUrl']?.toString(),
      city: firstNonEmpty([json['city'], geo['city']]),
      district: firstNonEmpty([json['district'], geo['district']]),
      latitude: asDouble(json['latitude'] ?? geo['latitude']),
      longitude: asDouble(json['longitude'] ?? geo['longitude']),
      ipAddress: firstNonEmpty([json['ipAddress'], geo['ipAddress']]),
    );
  }
}

class ChecklistItem {
  const ChecklistItem({
    required this.raw,
    this.id,
    this.name,
    this.task,
    this.description,
    this.isCompleted = false,
    this.comments = const [],
    this.legacyComment,
    this.attachments = const [],
    this.attachmentDetails = const [],
    this.startTime,
    this.endTime,
    this.timeSpent,
    this.sessions = const [],
    this.isOther = false,
    this.location,
  });

  /// The server row as received. Checklist writes PATCH a copy of this so
  /// fields this app does not model are never dropped on write-back.
  final Map<String, dynamic> raw;

  final String? id;
  final String? name;
  final String? task;
  final String? description;
  final bool isCompleted;
  final List<ChecklistNote> comments;

  /// Seeded rows store `comments` as a plain string instead of a note list.
  final String? legacyComment;
  final List<String> attachments;
  final List<ChecklistAttachment> attachmentDetails;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? timeSpent;
  final List<ChecklistSession> sessions;
  final bool isOther;
  final String? location;

  String get title => firstNonEmpty([name, task, description]) ?? 'Untitled task';

  bool get isRunning {
    if (sessions.isNotEmpty) return sessions.any((s) => s.isRunning);
    return startTime != null && endTime == null;
  }

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    final rawComments = json['comments'];
    final notes = <ChecklistNote>[];
    String? legacy;
    if (rawComments is List) {
      for (final c in rawComments) {
        if (c is Map) notes.add(ChecklistNote.fromJson(Map<String, dynamic>.from(c)));
      }
    } else if (rawComments != null) {
      final s = rawComments.toString().trim();
      if (s.isNotEmpty) legacy = s;
    }

    final rawSessions = json['sessions'];
    final sessions = rawSessions is List
        ? rawSessions
            .whereType<Map>()
            .map((s) => ChecklistSession.fromJson(Map<String, dynamic>.from(s)))
            .toList()
        : const <ChecklistSession>[];

    final rawAttachments = json['attachments'];
    final attachments = rawAttachments is List
        ? rawAttachments.map((a) => a.toString()).where((a) => a.isNotEmpty).toList()
        : const <String>[];

    final rawDetails = json['attachmentDetails'];
    final details = rawDetails is List
        ? rawDetails
            .whereType<Map>()
            .map((d) => ChecklistAttachment.fromJson(Map<String, dynamic>.from(d)))
            .toList()
        : const <ChecklistAttachment>[];

    return ChecklistItem(
      raw: json,
      id: json['id']?.toString(),
      name: json['name']?.toString(),
      task: json['task']?.toString(),
      description: json['description']?.toString(),
      isCompleted: asBool(json['isCompleted'] ?? json['completed']) ?? false,
      comments: notes,
      legacyComment: legacy,
      attachments: attachments,
      attachmentDetails: details,
      startTime: asDate(json['startTime']),
      endTime: asDate(json['endTime']),
      timeSpent: asInt(json['timeSpent']),
      sessions: sessions,
      isOther: asBool(json['isOther']) ?? false,
      location: json['location']?.toString(),
    );
  }

  static List<ChecklistItem> listFrom(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => ChecklistItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
