import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../core/capture/capture_services.dart';
import '../core/offline/sync_client.dart';
import '../domain/checklist.dart';
import '../domain/maintenance_record.dart';

/// Writes to a single checklist item. Every call goes through `syncRequest`, so
/// work done in a plant room with no signal queues and replays in order. The
/// web only queues the tick and voice notes; timer sessions and photos there
/// fail outright offline, which the checklist cannot afford on a phone.
/// What was written, plus the exact patch that was sent. The caller applies
/// the patch to its own copy so a change made offline shows immediately —
/// a refetch there only returns the cached record, which does not have it yet.
class ChecklistWrite {
  const ChecklistWrite({required this.synced, required this.updates});

  final bool synced;
  final Map<String, dynamic> updates;
}

class ChecklistRepository {
  ChecklistRepository(this._sync) : _uuid = const Uuid();

  final SyncClient _sync;
  final Uuid _uuid;

  String _endpoint(OrderType type, String recordId) =>
      '/api/fm/${type.checklistPath}/$recordId/checklist';

  /// The server merges only these keys onto the stored item; anything else in
  /// the body is ignored. `attachmentDetails` is one of the ignored ones, so
  /// names and dates never survive a round trip.
  Future<ChecklistWrite> _put(
    OrderType type,
    String recordId,
    int index,
    Map<String, dynamic> updates, {
    required String label,
    QueuedAttachment? attachment,
  }) async {
    final write = await _sync.syncRequest(
      'put',
      _endpoint(type, recordId),
      data: {'checklistIndex': index, ...updates},
      label: label,
      attachment: attachment,
      entityType: type.name,
      entityId: recordId,
    );
    return ChecklistWrite(synced: write.synced, updates: updates);
  }

  Future<ChecklistWrite> setCompleted(
    OrderType type,
    String recordId,
    int index, {
    required bool isCompleted,
  }) => _put(type, recordId, index, {
    'isCompleted': isCompleted,
  }, label: 'Checklist item');

  /// Opens a new session. `startTime` is kept at the top level too, because the
  /// server derives the record's own `startedDate` from the first one it sees.
  Future<ChecklistWrite> startSession(
    OrderType type,
    String recordId,
    int index, {
    required ChecklistItem item,
    CapturedPhoto? facePhoto,
    CapturedLocation? location,
  }) {
    final placeholder = facePhoto == null
        ? null
        : '__pending_face_${_uuid.v4()}__';

    return _put(
      type,
      recordId,
      index,
      startUpdates(
        item: item,
        now: DateTime.now().toUtc(),
        facePlaceholder: placeholder,
        location: location,
      ),
      label: 'Start task timer',
      attachment: facePhoto == null
          ? null
          : QueuedAttachment(
              bytes: facePhoto.bytes,
              fileName: facePhoto.fileName,
              placeholder: placeholder!,
              field: 'image',
            ),
    );
  }

  /// Closes the open session and re-totals the item. A legacy item that was
  /// started before sessions existed gets one synthesised from its `startTime`.
  Future<ChecklistWrite> stopSession(
    OrderType type,
    String recordId,
    int index, {
    required ChecklistItem item,
    CapturedPhoto? facePhoto,
    CapturedLocation? location,
  }) {
    final placeholder = facePhoto == null
        ? null
        : '__pending_face_${_uuid.v4()}__';

    return _put(
      type,
      recordId,
      index,
      stopUpdates(
        item: item,
        now: DateTime.now().toUtc(),
        facePlaceholder: placeholder,
        location: location,
      ),
      label: 'Stop task timer',
      attachment: facePhoto == null
          ? null
          : QueuedAttachment(
              bytes: facePhoto.bytes,
              fileName: facePhoto.fileName,
              placeholder: placeholder!,
              field: 'image',
            ),
    );
  }

  /// Appends a note. A recording queued offline writes a placeholder into the
  /// note body, swapped for the uploaded URL when the queue flushes.
  Future<ChecklistWrite> addNote(
    OrderType type,
    String recordId,
    int index, {
    required ChecklistItem item,
    required String text,
    VoiceRecording? voice,
  }) {
    final placeholder = voice == null
        ? null
        : '__pending_audio_${_uuid.v4()}__';

    final note = <String, dynamic>{
      'text': text,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'audioUrl': ?placeholder,
      'durationSeconds': ?voice?.duration.inSeconds,
    };

    return _put(
      type,
      recordId,
      index,
      {
        'comments': [..._existingNotes(item), note],
      },
      label: voice == null ? 'Checklist note' : 'Checklist voice note',
      attachment: voice == null
          ? null
          : QueuedAttachment(
              bytes: voice.bytes,
              fileName: voice.fileName,
              placeholder: placeholder!,
              field: 'file',
            ),
    );
  }

  /// A seeded item stores `comments` as a plain string; it becomes the first
  /// note rather than being thrown away.
  List<Map<String, dynamic>> _existingNotes(ChecklistItem item) {
    final raw = item.raw['comments'];
    if (raw is List) {
      return [
        for (final note in raw)
          if (note is Map) Map<String, dynamic>.from(note),
      ];
    }
    final legacy = raw?.toString().trim();
    if (legacy == null || legacy.isEmpty) return [];
    return [
      {'text': legacy, 'createdAt': DateTime.now().toUtc().toIso8601String()},
    ];
  }

  Future<ChecklistWrite> addAttachment(
    OrderType type,
    String recordId,
    int index, {
    required ChecklistItem item,
    required CapturedPhoto photo,
  }) {
    final placeholder = '__pending_photo_${_uuid.v4()}__';
    return _put(
      type,
      recordId,
      index,
      {
        'attachments': [...item.attachments, placeholder],
      },
      label: 'Checklist photo',
      attachment: QueuedAttachment(
        bytes: photo.bytes,
        fileName: photo.fileName,
        placeholder: placeholder,
        field: 'image',
      ),
    );
  }

  Future<ChecklistWrite> removeAttachment(
    OrderType type,
    String recordId,
    int index, {
    required ChecklistItem item,
    required String url,
  }) => _put(type, recordId, index, {
    'attachments': [
      for (final a in item.attachments)
        if (a != url) a,
    ],
  }, label: 'Remove checklist photo');

  /// A work order carries a single spoken note on the record itself, not per
  /// checklist item. Recording again replaces the previous one.
  Future<ChecklistWrite> setRecordVoiceNote(
    OrderType type,
    String recordId, {
    VoiceRecording? voice,
  }) async {
    final placeholder = voice == null
        ? null
        : '__pending_audio_${_uuid.v4()}__';
    final updates = <String, dynamic>{'notesAudioUrl': placeholder};

    final write = await _sync.syncRequest(
      'put',
      '/api/fm/${type.entityPath}/$recordId',
      data: updates,
      label: voice == null ? 'Remove voice note' : 'Work order voice note',
      attachment: voice == null
          ? null
          : QueuedAttachment(
              bytes: voice.bytes,
              fileName: voice.fileName,
              placeholder: placeholder!,
              field: 'file',
            ),
      entityType: type.name,
      entityId: recordId,
    );
    return ChecklistWrite(synced: write.synced, updates: updates);
  }

  /// "Other" items are appended to the record itself, not through the
  /// checklist endpoint, which can only address an existing index.
  Future<SyncedWrite> addOtherItem(
    OrderType type,
    MaintenanceRecord record, {
    required String description,
  }) {
    final text = description.trim();
    final existing = record.raw['checklists'];
    return _sync.syncRequest(
      'put',
      '/api/fm/${type.entityPath}/${record.id}',
      entityType: type.name,
      entityId: record.id,
      data: {
        'checklists': [
          ...existing is List ? existing : const [],
          {
            // The admin edit page keys its list off this id and deletes by it;
            // without one, every id-less item shares a key and deletes together.
            'id':
                'other-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4().substring(0, 7)}',
            'name': text,
            'task': text,
            'description': text,
            'isCompleted': false,
            'isOther': true,
            'comments': <dynamic>[],
            'attachments': <dynamic>[],
            'sessions': <dynamic>[],
            'timeSpent': 0,
          },
        ],
      },
      label: 'Add other task',
    );
  }

  /// Digital-signature sign-off (2026-09-09): appended to the record the same
  /// way `addOtherItem` above appends an "Other" item — same PUT to the
  /// record entity, same full-`checklists`-array replace — because the
  /// server's `checklistCloseGuard.ts` reads the signature out of that same
  /// JSON array, not a new column. The one difference from `addOtherItem` is
  /// the image: the drawn PNG rides through the SAME `QueuedAttachment`
  /// placeholder-substitution path every other attachment in this app uses
  /// (see `sync_client.dart`), so a signature captured with no signal queues
  /// and uploads on reconnect exactly like a checklist photo or voice note —
  /// it must not become a direct/non-queued upload, which would regress the
  /// offline guarantee for this one field.
  ///
  /// Field shape matches the web's `handleSaveSignature`
  /// (`maintenance-checklist-v2.tsx`) exactly: `isCompleted`, `isOther`,
  /// `isSignature`, `signatureUrl`, `signerName`, `signedAt`.
  Future<SyncedWrite> addSignatureItem(
    OrderType type,
    MaintenanceRecord record, {
    required Uint8List pngBytes,
    String? signerName,
  }) {
    final placeholder = '__pending_signature_${_uuid.v4()}__';
    final existing = record.raw['checklists'];
    final name = signerName?.trim();

    return _sync.syncRequest(
      'put',
      '/api/fm/${type.entityPath}/${record.id}',
      entityType: type.name,
      entityId: record.id,
      data: {
        'checklists': [
          ...existing is List ? existing : const [],
          {
            'id': 'signature-${DateTime.now().millisecondsSinceEpoch}',
            'name': 'Technician Signature',
            'task': 'Technician Signature',
            'description':
                'Digital signature confirming this work order was completed.',
            'isCompleted': true,
            'isOther': true,
            'isSignature': true,
            'signatureUrl': placeholder,
            if (name != null && name.isNotEmpty) 'signerName': name,
            'signedAt': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      },
      label: 'Technician signature',
      attachment: QueuedAttachment(
        bytes: pngBytes,
        fileName: 'signature.png',
        placeholder: placeholder,
        field: 'image',
      ),
    );
  }

  /// Body for opening a session. `startTime` is repeated at the top level
  /// because the server derives the record's own `startedDate` from the first
  /// one it sees.
  static Map<String, dynamic> startUpdates({
    required ChecklistItem item,
    required DateTime now,
    String? facePlaceholder,
    CapturedLocation? location,
  }) {
    final startTime = now.toIso8601String();
    return {
      'startTime': startTime,
      'endTime': null,
      'sessions': [
        ..._rawSessions(item),
        {
          'startTime': startTime,
          'faceCaptureUrl': ?facePlaceholder,
          'latitude': ?location?.latitude,
          'longitude': ?location?.longitude,
          'city': ?location?.city,
          'district': ?location?.district,
          'timeSpent': 0,
        },
      ],
    };
  }

  /// Body for closing the open session. An item started before sessions
  /// existed gets one synthesised from its top-level `startTime`, and the
  /// item's `timeSpent` is re-totalled across every session.
  static Map<String, dynamic> stopUpdates({
    required ChecklistItem item,
    required DateTime now,
    String? facePlaceholder,
    CapturedLocation? location,
  }) {
    final sessions = _rawSessions(item);
    if (sessions.isEmpty && item.startTime != null && item.endTime == null) {
      sessions.add({'startTime': item.startTime!.toUtc().toIso8601String()});
    }

    final activeIndex = sessions.indexWhere((s) => s['endTime'] == null);
    var totalMinutes = 0;

    if (activeIndex != -1) {
      final active = sessions[activeIndex];
      final start = DateTime.tryParse('${active['startTime']}');
      sessions[activeIndex] = {
        ...active,
        'endTime': now.toIso8601String(),
        'timeSpent': start == null ? 0 : now.difference(start).inMinutes,
        'endFaceCaptureUrl': ?facePlaceholder,
      };
      for (final s in sessions) {
        final spent = s['timeSpent'];
        if (spent is num) totalMinutes += spent.toInt();
      }
    } else if (item.startTime != null) {
      totalMinutes = now.difference(item.startTime!.toUtc()).inMinutes;
    }

    return {
      'endTime': now.toIso8601String(),
      'timeSpent': totalMinutes,
      'sessions': sessions,
      'latitude': ?location?.latitude,
      'longitude': ?location?.longitude,
      'city': ?location?.city,
      'district': ?location?.district,
    };
  }

  static List<Map<String, dynamic>> _rawSessions(ChecklistItem item) {
    final raw = item.raw['sessions'];
    if (raw is! List) return [];
    return [
      for (final s in raw)
        if (s is Map) Map<String, dynamic>.from(s),
    ];
  }
}
