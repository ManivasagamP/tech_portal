import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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
    this.attachment,
    this.attachmentName,
    this.attachmentField,
    this.placeholder,
  });

  final String clientMutationId;
  final String method;
  final String url;
  final dynamic body;
  final String label;
  final int attempts;
  final DateTime createdAt;
  final Uint8List? attachment;
  final String? attachmentName;

  /// `file` (POST /api/upload/file) or `image` (POST /api/upload/image).
  final String? attachmentField;

  /// Token inside [body] that gets replaced by the uploaded URL on flush.
  final String? placeholder;

  bool get hasAttachment => attachment != null && attachmentField != null;

  factory PendingMutation.fromRow(Map<String, Object?> row) => PendingMutation(
        clientMutationId: row['client_mutation_id'] as String,
        method: row['method'] as String,
        url: row['url'] as String,
        body: row['body'] == null ? null : jsonDecode(row['body'] as String),
        label: row['label'] as String? ?? 'Change',
        attempts: row['attempts'] as int? ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        attachment: row['attachment'] as Uint8List?,
        attachmentName: row['attachment_name'] as String?,
        attachmentField: row['attachment_field'] as String?,
        placeholder: row['placeholder'] as String?,
      );

  Map<String, Object?> toRow() => {
        'client_mutation_id': clientMutationId,
        'method': method,
        'url': url,
        'body': body == null ? null : jsonEncode(body),
        'label': label,
        'attempts': attempts,
        'created_at': createdAt.millisecondsSinceEpoch,
        'attachment': attachment,
        'attachment_name': attachmentName,
        'attachment_field': attachmentField,
        'placeholder': placeholder,
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
  const CachedEntity({required this.body, required this.cachedAt, required this.ttlMs});

  final dynamic body;
  final DateTime cachedAt;
  final int ttlMs;

  bool get isExpired =>
      DateTime.now().difference(cachedAt).inMilliseconds > ttlMs;
}

class OfflineDb {
  OfflineDb._(this._db);

  static const _fileName = 'fusion_eco_offline.db';
  static const _conflictCap = 50;

  final Database _db;

  static Future<OfflineDb> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, _fileName),
      version: 1,
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
            attachment BLOB,
            attachment_name TEXT,
            attachment_field TEXT,
            placeholder TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_pending_created_at ON pending_mutations (created_at)',
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
      },
    );
    return OfflineDb._(db);
  }

  Future<void> enqueue(PendingMutation mutation) async {
    await _db.insert(
      'pending_mutations',
      mutation.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Oldest first — replay order is what keeps RCA → downtime → complete correct.
  Future<List<PendingMutation>> listMutations() async {
    final rows = await _db.query('pending_mutations', orderBy: 'created_at ASC');
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

  Future<void> writeCache(String url, dynamic body, Duration ttl) => _db.insert(
        'cached_entities',
        {
          'url': url,
          'body': jsonEncode(body),
          'cached_at': DateTime.now().millisecondsSinceEpoch,
          'ttl_ms': ttl.inMilliseconds,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<String?> readMeta(String key) async {
    final rows = await _db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> writeMeta(String key, String value) => _db.insert(
        'sync_meta',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

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

  Future<void> wipe() async {
    await _db.delete('pending_mutations');
    await _db.delete('cached_entities');
    await _db.delete('sync_meta');
    await _db.delete('conflicts');
  }
}
