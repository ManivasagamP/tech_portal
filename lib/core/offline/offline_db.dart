import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
// FR-4.1/NFR-1 — SQLCipher build of sqflite, same API surface, so this is
// the only file in the app that needs to know the store is encrypted.
import 'package:sqflite_sqlcipher/sqflite.dart';

/// One queued upload inside a [PendingMutation] — a photo, a voice note, a
/// face capture. Uploaded independently on flush and its own [placeholder]
/// in the mutation body substituted with the resulting URL; [uploadedUrl] is
/// persisted back to the row the moment that upload succeeds (FR-4.7), so a
/// later retry on the same mutation — another attachment failing, a 5xx on
/// the request itself, the app getting killed mid-flush — does not re-upload
/// bytes that already landed.
class PendingAttachment {
  const PendingAttachment({
    required this.bytes,
    required this.fileName,
    required this.field,
    required this.placeholder,
    this.uploadedUrl,
  });

  final Uint8List bytes;
  final String fileName;

  /// `file` (POST /api/upload/file) or `image` (POST /api/upload/image).
  final String field;

  /// Token inside the mutation body replaced by the uploaded URL.
  final String placeholder;

  final String? uploadedUrl;

  factory PendingAttachment.fromJson(Map<String, dynamic> json) =>
      PendingAttachment(
        bytes: base64Decode(json['bytesBase64'] as String),
        fileName: json['fileName'] as String,
        field: json['field'] as String,
        placeholder: json['placeholder'] as String,
        uploadedUrl: json['uploadedUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'bytesBase64': base64Encode(bytes),
    'fileName': fileName,
    'field': field,
    'placeholder': placeholder,
    'uploadedUrl': ?uploadedUrl,
  };

  PendingAttachment withUploadedUrl(String url) => PendingAttachment(
    bytes: bytes,
    fileName: fileName,
    field: field,
    placeholder: placeholder,
    uploadedUrl: url,
  );
}

/// Mirrors the web portal's IndexedDB stores: a mutation queue, a GET cache, a
/// meta table and a capped conflict log.
class PendingMutation {
  const PendingMutation({
    required this.clientMutationId,
    required this.method,
    required this.url,
    required this.body,
    required this.label,
    required this.attempts,
    required this.createdAt,
    this.attachments = const [],
    this.entityType,
    this.entityId,
  });

  final String clientMutationId;
  final String method;
  final String url;
  final dynamic body;
  final String label;
  final int attempts;
  final DateTime createdAt;

  /// FR-4.7 — zero or more queued uploads this mutation's body references by
  /// placeholder. Most mutations have none; a field verification can have up
  /// to 8 (one per photo), each uploaded and resolved independently.
  final List<PendingAttachment> attachments;

  /// The order this write belongs to — an [OrderType.name], not its slug —
  /// and its record id. Stamped by the repository at enqueue time rather than
  /// parsed back out of [url]: the URL shape differs per endpoint (downtime's
  /// path puts a fixed segment before the record's own vocabulary), so it is
  /// not reliably reversible. Null for a request that never went through a
  /// [PendingMutation]-aware repository call. Used only to group and label
  /// the Sync Center list — never sent to the server.
  final String? entityType;
  final String? entityId;

  bool get hasAttachments => attachments.isNotEmpty;

  factory PendingMutation.fromRow(Map<String, Object?> row) {
    final attachmentsJson = row['attachments_json'] as String?;
    List<PendingAttachment> attachments;
    if (attachmentsJson != null && attachmentsJson.isNotEmpty) {
      attachments = (jsonDecode(attachmentsJson) as List)
          .map((e) => PendingAttachment.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      // A row queued before the FR-4.7 migration — its one attachment (if
      // any) still lives in the old singular columns rather than
      // `attachments_json`. Read it back the same way so an in-flight queue
      // survives the app update instead of silently dropping its photo.
      final legacyBytes = row['attachment'] as Uint8List?;
      final legacyField = row['attachment_field'] as String?;
      attachments = legacyBytes != null && legacyField != null
          ? [
              PendingAttachment(
                bytes: legacyBytes,
                fileName: row['attachment_name'] as String? ?? 'attachment',
                field: legacyField,
                placeholder: row['placeholder'] as String? ?? '',
              ),
            ]
          : const [];
    }
    return PendingMutation(
      clientMutationId: row['client_mutation_id'] as String,
      method: row['method'] as String,
      url: row['url'] as String,
      body: row['body'] == null ? null : jsonDecode(row['body'] as String),
      label: row['label'] as String? ?? 'Change',
      attempts: row['attempts'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      attachments: attachments,
      entityType: row['entity_type'] as String?,
      entityId: row['entity_id'] as String?,
    );
  }

  Map<String, Object?> toRow() => {
    'client_mutation_id': clientMutationId,
    'method': method,
    'url': url,
    'body': body == null ? null : jsonEncode(body),
    'label': label,
    'attempts': attempts,
    'created_at': createdAt.millisecondsSinceEpoch,
    'attachments_json': attachments.isEmpty
        ? null
        : jsonEncode(attachments.map((a) => a.toJson()).toList()),
    'entity_type': entityType,
    'entity_id': entityId,
  };
}

class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.label,
    required this.url,
    required this.reason,
    required this.at,
    required this.dropped,
  });

  final int id;
  final String label;
  final String url;
  final String reason;
  final DateTime at;
  final bool dropped;

  factory SyncConflict.fromRow(Map<String, Object?> row) => SyncConflict(
    id: row['id'] as int,
    label: row['label'] as String? ?? 'Change',
    url: row['url'] as String? ?? '',
    reason: row['reason'] as String? ?? '',
    at: DateTime.fromMillisecondsSinceEpoch(row['at'] as int),
    dropped: (row['dropped'] as int? ?? 1) == 1,
  );
}

class CachedEntity {
  const CachedEntity({
    required this.body,
    required this.cachedAt,
    required this.ttlMs,
  });

  final dynamic body;
  final DateTime cachedAt;
  final int ttlMs;

  bool get isExpired =>
      DateTime.now().difference(cachedAt).inMilliseconds > ttlMs;
}

/// A resolved c2o asset, cached offline so a later scan of the same tag
/// answers from the local store — see FR-1.1. Keyed by `assetId`, but also
/// carries `assetReferenceId` because the tokenless general Asset label
/// (`AssetLabel.tsx`) bakes that human-readable id into its QR instead of the
/// real uuid, and a lookup needs to match either one.
class CachedC2oAsset {
  const CachedC2oAsset({
    required this.assetId,
    required this.claims,
    required this.cachedAt,
    this.assetReferenceId,
    this.scanToken,
    this.packStamp,
  });

  final String assetId;
  final String? assetReferenceId;

  /// Null for an asset cached from the tokenless general label.
  final String? scanToken;

  /// The full `resolveScan()` response body, unpacked lazily by FR-2's
  /// display screen rather than re-shaped here.
  final Map<String, dynamic> claims;
  final DateTime cachedAt;

  /// The route pack's "as-of" stamp (SR-2), once FR-5 downloads packs in
  /// bulk. Null for an asset cached one-at-a-time via a live scan.
  final String? packStamp;

  factory CachedC2oAsset.fromRow(Map<String, Object?> row) => CachedC2oAsset(
    assetId: row['asset_id'] as String,
    assetReferenceId: row['asset_reference_id'] as String?,
    scanToken: row['scan_token'] as String?,
    claims: Map<String, dynamic>.from(jsonDecode(row['claims'] as String) as Map),
    cachedAt: DateTime.fromMillisecondsSinceEpoch(row['cached_at'] as int),
    packStamp: row['pack_stamp'] as String?,
  );

  Map<String, Object?> toRow() => {
    'asset_id': assetId,
    'asset_reference_id': assetReferenceId,
    'scan_token': scanToken,
    'claims': jsonEncode(claims),
    'cached_at': cachedAt.millisecondsSinceEpoch,
    'pack_stamp': packStamp,
  };
}

/// The c2o-cache operations `C2oAssetResolver` and the FR-1.6 manual search
/// need, pulled out of [OfflineDb] so a test can fake them without touching
/// sqflite.
abstract interface class C2oAssetCache {
  Future<CachedC2oAsset?> getC2oAsset(String idOrReference);
  Future<void> upsertC2oAsset(CachedC2oAsset asset);

  /// Every asset in today's downloaded route — FR-1.6 searches this list
  /// entirely on-device, never the network, since a technician reaching for
  /// manual search has usually already established there is no tag to scan.
  Future<List<CachedC2oAsset>> listC2oAssets();
}

/// A structured, countable "tag missing/unreadable" report (FR-1.7),
/// captured against an asset found via manual search (FR-1.6) rather than
/// scanned. Local-only for now: the server has no field for this yet
/// (SR-6) and there is no submission flow to send it through (FR-3/FR-4)
/// — this table is what makes the report real and countable on-device in
/// the meantime, instead of it disappearing into a notes field.
enum TagIssueReason { missing, unreadable }

class TagIssueReport {
  const TagIssueReport({
    this.id,
    required this.assetId,
    this.assetReferenceId,
    this.assetName,
    required this.reason,
    this.note,
    required this.reportedAt,
  });

  final int? id;
  final String assetId;
  final String? assetReferenceId;
  final String? assetName;
  final TagIssueReason reason;
  final String? note;
  final DateTime reportedAt;

  factory TagIssueReport.fromRow(Map<String, Object?> row) => TagIssueReport(
    id: row['id'] as int?,
    assetId: row['asset_id'] as String,
    assetReferenceId: row['asset_reference_id'] as String?,
    assetName: row['asset_name'] as String?,
    reason: TagIssueReason.values.byName(row['reason'] as String),
    note: row['note'] as String?,
    reportedAt: DateTime.fromMillisecondsSinceEpoch(row['reported_at'] as int),
  );

  Map<String, Object?> toRow() => {
    'asset_id': assetId,
    'asset_reference_id': assetReferenceId,
    'asset_name': assetName,
    'reason': reason.name,
    'note': note,
    'reported_at': reportedAt.millisecondsSinceEpoch,
  };
}

abstract interface class TagIssueLog {
  Future<void> reportTagIssue(TagIssueReport report);
  Future<List<TagIssueReport>> listTagIssueReports();
}

/// FR-4.2 — the in-progress FR-3 capture form, autosaved continuously so a
/// force-quit or an OS kill (a phone call, low memory, a crash) never costs
/// the technician a half-filled check. One draft per asset; a fresh
/// [saveDraft] for the same [assetId] replaces the last one rather than
/// accumulating history — this is a save slot, not a log.
class VerificationDraft {
  const VerificationDraft({
    required this.assetId,
    required this.payload,
    required this.updatedAt,
  });

  final String assetId;

  /// Opaque to this layer — the screen owns the shape (result, observed
  /// fields, photos as base64, notes, the reinspection flag/reason, the GPS
  /// fix). Keeping it schemaless here means a new FR-3 field never needs a
  /// migration just to survive a crash.
  final Map<String, dynamic> payload;
  final DateTime updatedAt;

  factory VerificationDraft.fromRow(Map<String, Object?> row) => VerificationDraft(
    assetId: row['asset_id'] as String,
    payload: Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
  );

  Map<String, Object?> toRow() => {
    'asset_id': assetId,
    'payload': jsonEncode(payload),
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };
}

abstract interface class VerificationDraftStore {
  Future<void> saveDraft(String assetId, Map<String, dynamic> payload);
  Future<VerificationDraft?> getDraft(String assetId);
  Future<void> deleteDraft(String assetId);
}

class OfflineDb implements C2oAssetCache, TagIssueLog, VerificationDraftStore {
  OfflineDb._(this._db);

  static const _fileName = 'fusion_eco_offline.db';
  static const _conflictCap = 50;

  final Database _db;

  static Future<OfflineDb> open({required String passphrase}) async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, _fileName),
      password: passphrase,
      version: 7,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE pending_mutations (
            client_mutation_id TEXT PRIMARY KEY,
            method TEXT NOT NULL,
            url TEXT NOT NULL,
            body TEXT,
            label TEXT,
            attempts INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            attachments_json TEXT,
            entity_type TEXT,
            entity_id TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_pending_created_at ON pending_mutations (created_at)',
        );
        await db.execute(
          'CREATE INDEX idx_pending_entity ON pending_mutations (entity_type, entity_id)',
        );
        await db.execute('''
          CREATE TABLE cached_entities (
            url TEXT PRIMARY KEY,
            body TEXT NOT NULL,
            cached_at INTEGER NOT NULL,
            ttl_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_meta (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE conflicts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT,
            url TEXT,
            reason TEXT,
            at INTEGER NOT NULL,
            dropped INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute(_createC2oAssetsSql);
        await db.execute(
          'CREATE INDEX idx_c2o_assets_reference ON c2o_assets (asset_reference_id)',
        );
        await db.execute(_createTagIssueReportsSql);
        await db.execute(_createDraftsSql);
      },
      // v1 → v2: which order a queued write belongs to, for the Sync Center
      // list. Existing rows just come back with both columns null — they
      // still show up in the list, minus the order grouping.
      // v2 → v3: the c2o field-verification asset cache (FR-1.1).
      // v3 → v4: local tag-missing/unreadable reports (FR-1.7).
      // v4 → v5: FR-3 capture-form drafts (FR-4.2).
      // v5 → v6: multi-attachment queue rows, one upload per photo (FR-4.7).
      // v6 → v7: index the Sync Center's per-entity grouping (FR-4.9 — also
      // the first migration exercised live against a populated queue).
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE pending_mutations ADD COLUMN entity_type TEXT',
          );
          await db.execute(
            'ALTER TABLE pending_mutations ADD COLUMN entity_id TEXT',
          );
        }
        if (oldVersion < 3) {
          await db.execute(_createC2oAssetsSql);
          await db.execute(
            'CREATE INDEX idx_c2o_assets_reference ON c2o_assets (asset_reference_id)',
          );
        }
        if (oldVersion < 4) {
          await db.execute(_createTagIssueReportsSql);
        }
        if (oldVersion < 5) {
          await db.execute(_createDraftsSql);
        }
        if (oldVersion < 6) {
          await db.execute(
            'ALTER TABLE pending_mutations ADD COLUMN attachments_json TEXT',
          );
        }
        if (oldVersion < 7) {
          await db.execute(
            'CREATE INDEX idx_pending_entity ON pending_mutations (entity_type, entity_id)',
          );
        }
      },
    );
    return OfflineDb._(db);
  }

  static const _createC2oAssetsSql = '''
    CREATE TABLE c2o_assets (
      asset_id TEXT PRIMARY KEY,
      asset_reference_id TEXT,
      scan_token TEXT,
      claims TEXT NOT NULL,
      cached_at INTEGER NOT NULL,
      pack_stamp TEXT
    )
  ''';

  static const _createTagIssueReportsSql = '''
    CREATE TABLE tag_issue_reports (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      asset_id TEXT NOT NULL,
      asset_reference_id TEXT,
      asset_name TEXT,
      reason TEXT NOT NULL,
      note TEXT,
      reported_at INTEGER NOT NULL
    )
  ''';

  static const _createDraftsSql = '''
    CREATE TABLE verification_drafts (
      asset_id TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''';

  Future<void> enqueue(PendingMutation mutation) async {
    await _db.insert(
      'pending_mutations',
      mutation.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Oldest first — replay order is what keeps RCA → downtime → complete correct.
  Future<List<PendingMutation>> listMutations() async {
    final rows = await _db.query(
      'pending_mutations',
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingMutation.fromRow).toList();
  }

  Future<int> countMutations() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM pending_mutations'),
      ) ??
      0;

  Future<void> deleteMutation(String id) => _db.delete(
    'pending_mutations',
    where: 'client_mutation_id = ?',
    whereArgs: [id],
  );

  Future<void> bumpAttempts(String id, int attempts) => _db.update(
    'pending_mutations',
    {'attempts': attempts},
    where: 'client_mutation_id = ?',
    whereArgs: [id],
  );

  /// FR-4.7 — called right after each individual attachment upload succeeds
  /// during a flush, so a photo that already landed is never re-sent by a
  /// later retry on the same mutation.
  Future<void> updateMutationAttachments(
    String id,
    List<PendingAttachment> attachments,
  ) => _db.update(
    'pending_mutations',
    {
      'attachments_json': attachments.isEmpty
          ? null
          : jsonEncode(attachments.map((a) => a.toJson()).toList()),
    },
    where: 'client_mutation_id = ?',
    whereArgs: [id],
  );

  Future<CachedEntity?> readCache(String url) async {
    final rows = await _db.query(
      'cached_entities',
      where: 'url = ?',
      whereArgs: [url],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CachedEntity(
      body: jsonDecode(row['body'] as String),
      cachedAt: DateTime.fromMillisecondsSinceEpoch(row['cached_at'] as int),
      ttlMs: row['ttl_ms'] as int,
    );
  }

  Future<void> writeCache(String url, dynamic body, Duration ttl) =>
      _db.insert('cached_entities', {
        'url': url,
        'body': jsonEncode(body),
        'cached_at': DateTime.now().millisecondsSinceEpoch,
        'ttl_ms': ttl.inMilliseconds,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<String?> readMeta(String key) async {
    final rows = await _db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> writeMeta(String key, String value) => _db.insert('sync_meta', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> addConflict({
    required String label,
    required String url,
    required String reason,
    bool dropped = true,
  }) async {
    await _db.insert('conflicts', {
      'label': label,
      'url': url,
      'reason': reason,
      'at': DateTime.now().millisecondsSinceEpoch,
      'dropped': dropped ? 1 : 0,
    });
    await _db.rawDelete(
      'DELETE FROM conflicts WHERE id NOT IN '
      '(SELECT id FROM conflicts ORDER BY at DESC LIMIT $_conflictCap)',
    );
  }

  Future<List<SyncConflict>> listConflicts() async {
    final rows = await _db.query('conflicts', orderBy: 'at DESC');
    return rows.map(SyncConflict.fromRow).toList();
  }

  Future<void> deleteConflict(int id) =>
      _db.delete('conflicts', where: 'id = ?', whereArgs: [id]);

  Future<void> clearConflicts() => _db.delete('conflicts');

  @override
  Future<void> upsertC2oAsset(CachedC2oAsset asset) => _db.insert(
    'c2o_assets',
    asset.toRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  /// Matches on either the real asset id or the `assetReferenceId` baked
  /// into a tokenless general-label scan — see [CachedC2oAsset].
  @override
  Future<CachedC2oAsset?> getC2oAsset(String idOrReference) async {
    final rows = await _db.query(
      'c2o_assets',
      where: 'asset_id = ? OR asset_reference_id = ?',
      whereArgs: [idOrReference, idOrReference],
      limit: 1,
    );
    return rows.isEmpty ? null : CachedC2oAsset.fromRow(rows.first);
  }

  @override
  Future<List<CachedC2oAsset>> listC2oAssets() async {
    final rows = await _db.query('c2o_assets', orderBy: 'cached_at DESC');
    return rows.map(CachedC2oAsset.fromRow).toList();
  }

  @override
  Future<void> reportTagIssue(TagIssueReport report) =>
      _db.insert('tag_issue_reports', report.toRow());

  @override
  Future<List<TagIssueReport>> listTagIssueReports() async {
    final rows = await _db.query('tag_issue_reports', orderBy: 'reported_at DESC');
    return rows.map(TagIssueReport.fromRow).toList();
  }

  @override
  Future<void> saveDraft(String assetId, Map<String, dynamic> payload) => _db.insert(
    'verification_drafts',
    VerificationDraft(
      assetId: assetId,
      payload: payload,
      updatedAt: DateTime.now(),
    ).toRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  @override
  Future<VerificationDraft?> getDraft(String assetId) async {
    final rows = await _db.query(
      'verification_drafts',
      where: 'asset_id = ?',
      whereArgs: [assetId],
      limit: 1,
    );
    return rows.isEmpty ? null : VerificationDraft.fromRow(rows.first);
  }

  @override
  Future<void> deleteDraft(String assetId) => _db.delete(
    'verification_drafts',
    where: 'asset_id = ?',
    whereArgs: [assetId],
  );

  Future<void> wipe() async {
    await _db.delete('pending_mutations');
    await _db.delete('cached_entities');
    await _db.delete('sync_meta');
    await _db.delete('conflicts');
    await _db.delete('c2o_assets');
    await _db.delete('tag_issue_reports');
    await _db.delete('verification_drafts');
  }
}
