// ignore_for_file: prefer_initializing_formals — named params cannot be private
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../core/capture/capture_services.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../core/network/envelope.dart';
import '../core/offline/offline_db.dart';
import '../core/offline/sync_client.dart';
import '../core/snag/snag_media.dart';
import '../core/snag/snag_rules.dart';
import '../domain/snag.dart';

/// Who is acting. Technicians sign in with role `Technician`; the server
/// reads the real role off the JWT, this copy only drives the local rules.
class SnagActor {
  const SnagActor({required this.id, required this.name, this.role = 'Technician'});
  final String id;
  final String name;
  final String role;
}

/// Everything needed to raise one snag.
class SnagDraft {
  SnagDraft({
    required this.id,
    required this.context,
    required this.trade,
    required this.priority,
    this.issueType = 'defect',
    this.title,
    this.description,
    this.buildingId,
    this.floorId,
    this.spaceId,
    this.locationLabel,
    this.locationText,
    this.pin,
    this.assetId,
    this.assetName,
    this.assetReferenceId,
    this.surveyId,
    this.workOrderId,
    this.responsibleParty,
    this.dueDate,
    this.photos = const [],
    this.voice,
    this.lat,
    this.lng,
  });

  final String id;
  final SnagContext context;
  final String trade;
  final SnagPriority priority;
  final String issueType;
  final String? title;
  final String? description;
  final String? buildingId;
  final String? floorId;
  final String? spaceId;
  final String? locationLabel;
  final String? locationText;
  final SnagPin? pin;
  final String? assetId;
  final String? assetName;
  final String? assetReferenceId;
  final String? surveyId;
  final String? workOrderId;
  final String? responsibleParty;
  final DateTime? dueDate;
  final List<CapturedPhoto> photos;
  final VoiceRecording? voice;
  final double? lat;
  final double? lng;

  SnagDraftSignature signature({String? raisedBy}) => SnagDraftSignature(
    trade: trade,
    buildingId: buildingId,
    floorId: floorId,
    spaceId: spaceId,
    assetId: assetId,
    issueType: issueType,
    title: title,
    pin: pin,
    surveyId: surveyId,
    raisedBy: raisedBy,
  );
}

class SnagWriteResult {
  const SnagWriteResult({required this.snag, required this.synced});
  final Snag snag;

  /// false = saved on the device and queued; it syncs on its own.
  final bool synced;
}

/// A local rule refused the action before anything was written.
class SnagRuleException implements Exception {
  const SnagRuleException(this.failure);
  final SnagTransitionFailure failure;
  @override
  String toString() => failure.message;
}

/// Snag Assistant data access (docs/snag-assistant.md §6).
///
/// **Local first.** Every write lands in [SnagStore] before any network call,
/// so the UI is instant in a basement. The server write then goes through
/// [SyncClient.syncRequest] with `queueOnServerError: true`, which parks it
/// in the normal offline queue on no signal *or* a 5xx — including the
/// `503 SNAG_ENGINE_NOT_ENABLED` a server answers until its one migration
/// has run. The queue gives snags background upload, the Sync Center and
/// mutation-id idempotency for free.
///
/// **Merge on read.** [refresh] overwrites a local snag with the server's
/// copy unless a write for it is still queued (then the device is ahead).
/// A server rejection of a queued write goes to the conflict log through the
/// flush policy, the write leaves the queue, and the next refresh restores
/// the server's truth — the local optimistic state never wins for long.
///
/// **Self-heal.** A create that exhausted its retries (the server was down
/// or not yet enabled for longer than the retry budget) leaves a snag that is
/// still `localOnly` with nothing queued. [resendStranded] finds those and
/// queues them again once `GET /api/snags/engine` says the server can take them.
class SnagRepository {
  SnagRepository({
    required SyncClient sync,
    required ApiClient api,
    required SnagStore store,
    required SnagMedia media,
    Uuid? uuid,
  }) : _sync = sync,
       _api = api,
       _store = store,
       _media = media,
       _uuid = uuid ?? const Uuid();

  final SyncClient _sync;
  final ApiClient _api;
  final SnagStore _store;
  final SnagMedia _media;
  final Uuid _uuid;

  static const entityType = 'Snag';
  static const surveyEntityType = 'SnagSurvey';

  /// Building lists and trees change rarely and a walk can run for days
  /// offline, so they outlive the 24h default cache.
  static const _locationTtl = Duration(days: 30);

  SnagMedia get media => _media;

  String newId() => _uuid.v4();

  // -------------------------------------------------------------------------
  // Locations
  // -------------------------------------------------------------------------

  Future<List<SnagBuilding>> buildings() async {
    final read = await _sync.syncGet('/api/snags/locations/buildings', ttl: _locationTtl);
    return unwrapList(read.data).map(SnagBuilding.fromJson).where((b) => b.id.isNotEmpty).toList();
  }

  Future<SnagLocationTree?> tree(String buildingId) async {
    final read = await _sync.syncGet('/api/snags/locations/buildings/$buildingId', ttl: _locationTtl);
    final json = unwrapMap(read.data);
    return json.isEmpty ? null : SnagLocationTree.fromJson(json);
  }

  // -------------------------------------------------------------------------
  // Snags — reads
  // -------------------------------------------------------------------------

  Snag _fromRow(StoredSnagRow r) => Snag.fromJson({...r.json, 'localOnly': r.localOnly});

  Future<List<Snag>> local({String? buildingId}) async =>
      (await _store.listSnags(buildingId: buildingId)).map(_fromRow).toList();

  Future<Snag?> localById(String id) async {
    final row = await _store.getSnag(id);
    return row == null ? null : _fromRow(row);
  }

  /// Pulls one building's snags and merges them in. Returns false when the
  /// device is offline — the local store is then all there is, which is the
  /// normal case in the field rather than an error.
  Future<bool> refresh({required String buildingId}) async {
    final dynamic body;
    try {
      final res = await _api.get('/api/snags', query: {'buildingId': buildingId, 'limit': 2000});
      body = res.data;
    } on NetworkFailure {
      return false;
    }
    final data = unwrapMap(body);
    final items = data['items'] is List
        ? (data['items'] as List).whereType<Map>().map((e) => Snag.fromJson(Map<String, dynamic>.from(e))).toList()
        : <Snag>[];
    final pending = await _store.pendingEntityIds(entityType);
    for (final s in items) {
      if (pending.contains(s.id)) continue;
      await _saveServer(s);
    }
    // Prune only on a complete list: a truncated page must never delete rows.
    final total = asInt(data['total']) ?? items.length;
    if (total <= items.length) {
      await _store.pruneSnags(buildingId: buildingId, keepIds: {...items.map((s) => s.id), ...pending});
    }
    return true;
  }

  /// One snag straight from the server — a notification deep link can point
  /// at a snag this device has never listed. Null offline or when missing.
  Future<Snag?> fetchOne(String id) async {
    final pending = await _store.pendingEntityIds(entityType);
    if (pending.contains(id)) return localById(id);
    try {
      final res = await _api.get('/api/snags/$id');
      final data = unwrapMap(res.data);
      return data.isEmpty ? null : await _saveServer(Snag.fromJson(data));
    } on ApiFailure {
      return localById(id);
    }
  }

  Future<void> _saveLocal(Snag s) => _store.upsertSnag(
    id: s.id,
    json: s.toJson(),
    buildingId: s.buildingId,
    surveyId: s.surveyId,
    status: s.status.wire,
    localOnly: s.localOnly,
    updatedAt: s.updatedAt,
  );

  /// Saves a server copy, carrying over this device's own photo paths so
  /// the inspector keeps seeing their photos offline after sync.
  Future<Snag> _saveServer(Snag server) async {
    final existing = await localById(server.id);
    final paths = {
      for (final e in existing?.evidence ?? const <SnagEvidence>[])
        if (e.localPath != null) e.id: e.localPath,
    };
    final merged = server.copyWith(
      localOnly: false,
      evidence: [for (final e in server.evidence) paths.containsKey(e.id) ? e.withLocalPath(paths[e.id]) : e],
    );
    await _saveLocal(merged);
    return merged;
  }

  // -------------------------------------------------------------------------
  // Snags — writes
  // -------------------------------------------------------------------------

  static String _placeholder(String evidenceId) => '__pending_snag_${evidenceId}__';

  Future<(List<SnagEvidence>, List<QueuedAttachment>)> _capture({
    required String snagId,
    required String stage,
    required SnagActor actor,
    List<CapturedPhoto> photos = const [],
    VoiceRecording? voice,
    double? lat,
    double? lng,
  }) async {
    final evidence = <SnagEvidence>[];
    final uploads = <QueuedAttachment>[];
    final now = DateTime.now();
    for (final photo in photos) {
      final id = newId();
      final ext = photo.fileName.contains('.') ? photo.fileName.split('.').last.toLowerCase() : 'jpg';
      final path = await _media.saveOwn(snagId: snagId, evidenceId: id, bytes: photo.bytes, extension: ext);
      evidence.add(SnagEvidence(
        id: id,
        kind: 'photo',
        stage: stage,
        capturedAt: now,
        localPath: path,
        capturedBy: actor.id,
        capturedByName: actor.name,
        lat: lat,
        lng: lng,
      ));
      uploads.add(QueuedAttachment(
        bytes: photo.bytes,
        fileName: 'snag-$id.$ext',
        placeholder: _placeholder(id),
        field: 'image',
      ));
    }
    if (voice != null) {
      final id = newId();
      final path = await _media.saveOwn(snagId: snagId, evidenceId: id, bytes: voice.bytes, extension: 'm4a');
      evidence.add(SnagEvidence(
        id: id,
        kind: 'audio',
        stage: stage,
        capturedAt: now,
        localPath: path,
        capturedBy: actor.id,
        capturedByName: actor.name,
      ));
      uploads.add(QueuedAttachment(
        bytes: voice.bytes,
        fileName: 'snag-$id.m4a',
        placeholder: _placeholder(id),
      ));
    }
    return (evidence, uploads);
  }

  /// The wire shape of evidence: the URL is a placeholder the queue swaps
  /// for the uploaded file's URL at send time.
  static List<Map<String, dynamic>> _wireEvidence(List<SnagEvidence> evidence) => [
    for (final e in evidence)
      {
        'id': e.id,
        'kind': e.kind,
        'stage': e.stage,
        'url': e.url ?? _placeholder(e.id),
        'capturedAt': e.capturedAt.toUtc().toIso8601String(),
        if (e.lat != null && e.lng != null) 'geo': {'lat': e.lat, 'lng': e.lng},
      },
  ];

  static Map<String, dynamic> _createBody(Snag s) => {
    'id': s.id,
    'context': s.context.wire,
    'issueType': s.issueType,
    'trade': s.trade,
    'priority': s.priority.wire,
    'title': s.title,
    'description': ?s.description,
    'buildingId': ?s.buildingId,
    'floorId': ?s.floorId,
    'spaceId': ?s.spaceId,
    'locationLabel': ?s.locationLabel,
    'locationText': ?s.locationText,
    'locationPin': ?s.pin?.toJson(),
    'assetId': ?s.assetId,
    'assetName': ?s.assetName,
    'assetReferenceId': ?s.assetReferenceId,
    'surveyId': ?s.surveyId,
    'workOrderId': ?s.workOrderId,
    'responsibleParty': ?s.responsibleParty,
    'dueDate': ?s.dueDate?.toUtc().toIso8601String(),
    'clientCreatedAt': s.createdAt.toUtc().toIso8601String(),
    'evidence': _wireEvidence(s.evidence.where((e) => e.stage == 'before').toList()),
  };

  static String _defaultTitle(String trade, String issueType) {
    String cap(String w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}';
    return '${cap(trade.replaceAll('-', ' '))} ${issueType.replaceAll('-', ' ')}';
  }

  Future<SnagWriteResult> raise(SnagDraft d, SnagActor actor) async {
    final (evidence, uploads) = await _capture(
      snagId: d.id,
      stage: 'before',
      actor: actor,
      photos: d.photos,
      voice: d.voice,
      lat: d.lat,
      lng: d.lng,
    );
    final now = DateTime.now();
    final title = (d.title?.trim().isNotEmpty ?? false) ? d.title!.trim() : _defaultTitle(d.trade, d.issueType);
    final snag = Snag(
      id: d.id,
      context: d.context,
      issueType: d.issueType,
      trade: d.trade,
      priority: d.priority,
      title: title,
      description: (d.description?.trim().isEmpty ?? true) ? null : d.description!.trim(),
      status: SnagStatus.open,
      buildingId: d.buildingId,
      floorId: d.floorId,
      spaceId: d.spaceId,
      locationLabel: d.locationLabel,
      locationText: d.locationText,
      pin: d.pin,
      assetId: d.assetId,
      assetName: d.assetName,
      assetReferenceId: d.assetReferenceId,
      surveyId: d.surveyId,
      workOrderId: d.workOrderId,
      responsibleParty: d.responsibleParty,
      dueDate: d.dueDate,
      evidence: evidence,
      activity: [SnagActivity(id: newId(), at: now, type: 'raised', by: actor.id, byName: actor.name)],
      raisedBy: actor.id,
      raisedByName: actor.name,
      createdAt: now,
      updatedAt: now,
      localOnly: true,
    );
    await _saveLocal(snag);
    return _send(
      snag,
      () => _sync.syncRequest(
        'post',
        '/api/snags',
        data: _createBody(snag),
        label: 'Raise snag',
        attachments: uploads,
        entityType: entityType,
        entityId: snag.id,
        queueOnServerError: true,
      ),
      keepLocalOnHttpError: true,
    );
  }

  /// Sends one queued-capable write. On success the server's copy replaces
  /// the optimistic one. On a 4xx the optimistic change is rolled back to
  /// [rollbackTo] (the server said no, so the device must not pretend
  /// otherwise) — except for a create, which is kept on the device so the
  /// evidence is never lost to a rejected request.
  Future<SnagWriteResult> _send(
    Snag optimistic,
    Future<SyncedWrite> Function() call, {
    Snag? rollbackTo,
    bool keepLocalOnHttpError = false,
  }) async {
    try {
      final write = await call();
      if (!write.synced) return SnagWriteResult(snag: optimistic, synced: false);
      final data = unwrapMap(write.data);
      if (data.isEmpty) return SnagWriteResult(snag: optimistic, synced: true);
      final saved = await _saveServer(Snag.fromJson(data));
      return SnagWriteResult(snag: saved, synced: true);
    } on HttpFailure {
      if (!keepLocalOnHttpError && rollbackTo != null) await _saveLocal(rollbackTo);
      rethrow;
    }
  }

  Future<SnagWriteResult> transition(
    Snag snag,
    SnagAction action,
    SnagActor actor, {
    String? reason,
    String? note,
    List<CapturedPhoto> photos = const [],
  }) async {
    final stage = action == SnagAction.ready ? 'after' : 'extra';
    final (added, uploads) = await _capture(snagId: snag.id, stage: stage, actor: actor, photos: photos);
    final result = SnagRules.apply(
      snag,
      action,
      actorId: actor.id,
      actorName: actor.name,
      actorRole: actor.role,
      reason: reason,
      note: note,
      added: added,
      activityId: newId(),
    );
    final next = result.snag;
    if (next == null) throw SnagRuleException(result.failure!);
    await _saveLocal(next);
    return _send(
      next,
      () => _sync.syncRequest(
        'post',
        '/api/snags/${snag.id}/transition',
        data: {
          'action': action.name,
          'reason': ?reason,
          'note': ?note,
          'evidence': _wireEvidence(added),
        },
        label: 'Snag ${snag.displayRef}: ${action.name}',
        attachments: uploads,
        entityType: entityType,
        entityId: snag.id,
        queueOnServerError: true,
      ),
      rollbackTo: snag,
    );
  }

  /// Adds photos to an existing snag. [duplicateReport] is the "+1" from the
  /// duplicate guard: the same defect seen again, which also raises
  /// "Also reported by N".
  Future<SnagWriteResult> addEvidence(
    Snag snag,
    SnagActor actor, {
    List<CapturedPhoto> photos = const [],
    bool duplicateReport = false,
    String? note,
  }) async {
    final (added, uploads) = await _capture(snagId: snag.id, stage: 'extra', actor: actor, photos: photos);
    final now = DateTime.now();
    final next = snag.copyWith(
      evidence: [...snag.evidence, ...added],
      reportCount: snag.reportCount + (duplicateReport ? 1 : 0),
      updatedAt: now,
      activity: [
        ...snag.activity,
        SnagActivity(
          id: newId(),
          at: now,
          type: duplicateReport ? 'duplicate-report' : 'evidence',
          by: actor.id,
          byName: actor.name,
          note: note,
        ),
      ],
    );
    await _saveLocal(next);
    return _send(
      next,
      () => _sync.syncRequest(
        'post',
        '/api/snags/${snag.id}/evidence',
        data: {'evidence': _wireEvidence(added), 'duplicateReport': duplicateReport, 'note': ?note},
        label: duplicateReport ? 'Snag ${snag.displayRef}: also seen' : 'Snag ${snag.displayRef}: photo',
        attachments: uploads,
        entityType: entityType,
        entityId: snag.id,
        queueOnServerError: true,
      ),
      rollbackTo: snag,
    );
  }

  Future<SnagWriteResult> comment(Snag snag, SnagActor actor, String note) async {
    final now = DateTime.now();
    final next = snag.copyWith(
      updatedAt: now,
      activity: [
        ...snag.activity,
        SnagActivity(id: newId(), at: now, type: 'comment', by: actor.id, byName: actor.name, note: note),
      ],
    );
    await _saveLocal(next);
    return _send(
      next,
      () => _sync.syncRequest(
        'post',
        '/api/snags/${snag.id}/comments',
        data: {'note': note},
        label: 'Snag ${snag.displayRef}: comment',
        entityType: entityType,
        entityId: snag.id,
        queueOnServerError: true,
      ),
      rollbackTo: snag,
    );
  }

  /// UC-11 — online only and never queued: a suggestion that arrives an hour
  /// later is worthless. Null when offline or the assistant is unavailable;
  /// the compose card simply carries on without it.
  Future<SnagSuggestion?> assist(
    CapturedPhoto photo, {
    VoiceRecording? voice,
    String? hint,
    SnagContext context = SnagContext.operations,
  }) async {
    try {
      final res = await _api.post('/api/snags/assist', data: {
        'image': photo.dataUrl,
        'audio': ?voice?.dataUrl,
        'hint': ?hint,
        'context': context.wire,
      });
      final data = unwrapMap(res.data);
      return data.isEmpty ? null : SnagSuggestion.fromJson(data);
    } on ApiFailure {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Surveys
  // -------------------------------------------------------------------------

  Future<List<SnagSurvey>> surveys({String? buildingId}) async =>
      (await _store.listSurveys(buildingId: buildingId)).map(SnagSurvey.fromJson).toList();

  Future<SnagSurvey?> surveyById(String id) async {
    final json = await _store.getSurvey(id);
    return json == null ? null : SnagSurvey.fromJson(json);
  }

  Future<void> _saveSurvey(SnagSurvey s) => _store.upsertSurvey(
    id: s.id,
    json: s.toJson(),
    buildingId: s.buildingId,
    localOnly: s.localOnly,
    updatedAt: DateTime.now(),
  );

  Future<bool> refreshSurveys({required String buildingId}) async {
    final dynamic body;
    try {
      final res = await _api.get('/api/snags/surveys', query: {'buildingId': buildingId});
      body = res.data;
    } on NetworkFailure {
      return false;
    }
    final pending = await _store.pendingEntityIds(surveyEntityType);
    for (final json in unwrapList(body)) {
      final s = SnagSurvey.fromJson(json);
      if (s.id.isEmpty || pending.contains(s.id)) continue;
      await _saveSurvey(s.copyWith(localOnly: false));
    }
    return true;
  }

  Future<SnagSurvey> startSurvey({
    required String name,
    required SnagContext context,
    required SnagBuilding building,
    required SnagActor actor,
  }) async {
    final survey = SnagSurvey(
      id: newId(),
      name: name,
      context: context,
      buildingId: building.id,
      buildingName: building.name,
      startedBy: actor.id,
      startedByName: actor.name,
      startedAt: DateTime.now(),
      localOnly: true,
    );
    await _saveSurvey(survey);
    await _postSurvey(survey);
    return survey;
  }

  Future<void> _postSurvey(SnagSurvey survey) async {
    try {
      final write = await _sync.syncRequest(
        'post',
        '/api/snags/surveys',
        data: {
          'id': survey.id,
          'name': survey.name,
          'context': survey.context.wire,
          'buildingId': ?survey.buildingId,
          'buildingName': ?survey.buildingName,
          'startedAt': survey.startedAt.toUtc().toIso8601String(),
        },
        label: 'Start snag survey',
        entityType: surveyEntityType,
        entityId: survey.id,
        queueOnServerError: true,
      );
      if (write.synced) await _saveSurvey(survey.copyWith(localOnly: false));
    } on HttpFailure {
      // Kept on the device; [resendStranded] retries it.
    }
  }

  /// UC-2 room sweep. Replaces any earlier sweep of the same room.
  Future<SnagSurvey> sweep(
    SnagSurvey survey, {
    required SnagFloor floor,
    required SnagSpace space,
    required int snagCount,
    required SnagActor actor,
  }) async {
    final entry = SpaceSweep(
      spaceId: space.id,
      spaceName: space.name,
      floorId: floor.id,
      clear: snagCount == 0,
      snagCount: snagCount,
      at: DateTime.now(),
      by: actor.id,
      byName: actor.name,
    );
    final next = survey.copyWith(
      inspectedSpaces: [...survey.inspectedSpaces.where((s) => s.spaceId != space.id), entry],
    );
    await _saveSurvey(next);
    try {
      await _sync.syncRequest(
        'post',
        '/api/snags/surveys/${survey.id}/spaces',
        data: entry.toJson(),
        label: 'Room checked: ${space.name}',
        entityType: surveyEntityType,
        entityId: survey.id,
        queueOnServerError: true,
      );
    } on HttpFailure {
      // The sweep stays on the device; coverage still counts it locally.
    }
    return next;
  }

  Future<SnagSurvey> completeSurvey(SnagSurvey survey) async {
    final next = survey.copyWith(completed: true, completedAt: DateTime.now());
    await _saveSurvey(next);
    try {
      await _sync.syncRequest(
        'post',
        '/api/snags/surveys/${survey.id}/complete',
        label: 'Complete snag survey',
        entityType: surveyEntityType,
        entityId: survey.id,
        queueOnServerError: true,
      );
    } on HttpFailure {
      // Local state is what the app shows; nothing else depends on it.
    }
    return next;
  }

  // -------------------------------------------------------------------------
  // Self-heal and offline prep
  // -------------------------------------------------------------------------

  /// Re-queues creates that ran out of retries. Returns how many were
  /// re-queued. Does nothing offline or while the server is not enabled for
  /// snags — re-queuing then would only burn the retry budget again.
  Future<int> resendStranded({String? buildingId}) async {
    try {
      final res = await _api.get('/api/snags/engine');
      if (asBool(unwrapMap(res.data)['enabled']) != true) return 0;
    } on ApiFailure {
      return 0;
    }
    var count = 0;
    final pendingSurveys = await _store.pendingEntityIds(surveyEntityType);
    for (final s in await surveys(buildingId: buildingId)) {
      if (s.localOnly && !pendingSurveys.contains(s.id)) {
        await _postSurvey(s);
        count++;
      }
    }
    final pending = await _store.pendingEntityIds(entityType);
    for (final s in await local(buildingId: buildingId)) {
      if (!s.localOnly || pending.contains(s.id)) continue;
      final uploads = <QueuedAttachment>[];
      for (final e in s.evidence.where((e) => e.stage == 'before' && e.url == null)) {
        final path = e.localPath;
        if (path == null || !File(path).existsSync()) continue;
        uploads.add(QueuedAttachment(
          bytes: await File(path).readAsBytes(),
          fileName: 'snag-${e.id}.${e.isPhoto ? 'jpg' : 'm4a'}',
          placeholder: _placeholder(e.id),
          field: e.isPhoto ? 'image' : 'file',
        ));
      }
      final body = _createBody(s);
      // Only send evidence whose bytes are still on the device.
      final sendable = uploads.map((u) => u.placeholder).toSet();
      body['evidence'] = (body['evidence'] as List)
          .where((e) => sendable.contains((e as Map)['url']) || !(e['url'] as String).startsWith('__pending'))
          .toList();
      try {
        await _send(
          s,
          () => _sync.syncRequest(
            'post',
            '/api/snags',
            data: body,
            label: 'Raise snag (retry)',
            attachments: uploads,
            entityType: entityType,
            entityId: s.id,
            queueOnServerError: true,
          ),
          keepLocalOnHttpError: true,
        );
        count++;
      } on HttpFailure {
        // A 4xx on a create is a payload the server will never accept; it
        // stays on the device for the Sync Center rather than looping.
      }
    }
    return count;
  }

  /// "Download for offline": other people's photos of the building's live
  /// snags, so a verifier can compare before/after with no signal.
  Future<int> prefetchMedia({required String buildingId}) async {
    final snags = await local(buildingId: buildingId);
    return _media.prefetch(snags.where((s) => s.status.isLive).expand((s) => s.evidence));
  }
}
