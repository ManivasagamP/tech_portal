// ignore_for_file: prefer_initializing_formals — named params cannot be private
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../../app/env.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'offline_db.dart';
import 'queue_bus.dart';

class SyncedRead<T> {
  const SyncedRead({required this.data, required this.fromCache});
  final T data;
  final bool fromCache;
}

class SyncedWrite {
  const SyncedWrite({required this.synced, this.data});

  /// false means the mutation is parked in the queue and will replay on reconnect.
  final bool synced;
  final dynamic data;
}

class QueuedAttachment {
  const QueuedAttachment({
    required this.bytes,
    required this.fileName,
    required this.placeholder,
    this.field = 'file',
  });

  final Uint8List bytes;
  final String fileName;

  /// Token embedded in the mutation body, replaced by the uploaded URL on flush.
  final String placeholder;

  /// `file` → POST /api/upload/file, `image` → POST /api/upload/image.
  final String field;
}

/// Offline-aware transport. Reads fall back to cache on a network failure; writes
/// park in the queue on a network failure and replay in order. A 4xx/5xx always
/// propagates — replaying it could not succeed.
class SyncClient {
  SyncClient({
    required ApiClient api,
    required OfflineDb db,
    required QueueBus bus,
    Connectivity? connectivity,
  })  : _api = api,
        _db = db,
        _bus = bus,
        _connectivity = connectivity ?? Connectivity();

  final ApiClient _api;
  final OfflineDb _db;
  final QueueBus _bus;
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _flushing = false;

  OfflineDb get db => _db;
  QueueBus get bus => _bus;

  Future<bool> get isOffline async {
    final results = await _connectivity.checkConnectivity();
    return results.every((r) => r == ConnectivityResult.none);
  }

  /// Flush on start and whenever connectivity comes back.
  void startAutoFlush() {
    _connectivitySub ??= _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) unawaited(flushQueue());
    });
    unawaited(flushQueue());
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  String cacheKey(String url, Map<String, dynamic>? query) {
    if (query == null || query.isEmpty) return url;
    final keys = query.keys.toList()..sort();
    final qs = keys.map((k) => '$k=${query[k]}').join('&');
    return '$url?$qs';
  }

  Future<SyncedRead<dynamic>> syncGet(
    String url, {
    Map<String, dynamic>? query,
    Duration ttl = Env.cacheTtl,
  }) async {
    final key = cacheKey(url, query);

    if (await isOffline) {
      final cached = await _db.readCache(key);
      if (cached != null && !cached.isExpired) {
        return SyncedRead(data: cached.body, fromCache: true);
      }
    }

    try {
      final response = await _api.get(url, query: query);
      await _db.writeCache(key, response.data, ttl);
      return SyncedRead(data: response.data, fromCache: false);
    } on NetworkFailure {
      final cached = await _db.readCache(key);
      if (cached != null && !cached.isExpired) {
        return SyncedRead(data: cached.body, fromCache: true);
      }
      rethrow;
    }
  }

  Future<SyncedWrite> syncRequest(
    String method,
    String url, {
    dynamic data,
    required String label,
    QueuedAttachment? attachment,
  }) async {
    final mutationId = _api.newMutationId();

    if (await isOffline) {
      await _enqueue(mutationId, method, url, data, label, attachment);
      return const SyncedWrite(synced: false);
    }

    try {
      var body = data;
      if (attachment != null) {
        final uploadedUrl = await uploadBytes(
          bytes: attachment.bytes,
          fileName: attachment.fileName,
          field: attachment.field,
        );
        body = _substitute(body, attachment.placeholder, uploadedUrl);
      }
      final response = await _api.request(
        method,
        url,
        data: body,
        mutationId: mutationId,
      );
      return SyncedWrite(synced: true, data: response.data);
    } on NetworkFailure {
      await _enqueue(mutationId, method, url, data, label, attachment);
      return const SyncedWrite(synced: false);
    }
  }

  Future<void> _enqueue(
    String mutationId,
    String method,
    String url,
    dynamic data,
    String label,
    QueuedAttachment? attachment,
  ) async {
    await _db.enqueue(
      PendingMutation(
        clientMutationId: mutationId,
        method: method,
        url: url,
        body: data,
        label: label,
        attempts: 0,
        createdAt: DateTime.now(),
        attachment: attachment?.bytes,
        attachmentName: attachment?.fileName,
        attachmentField: attachment?.field,
        placeholder: attachment?.placeholder,
      ),
    );
    _bus.notify();
  }

  /// Replays oldest-first and stops at the first network failure so ordering holds.
  /// A 4xx (or the attempt cap) drops the mutation into the conflict log; a 5xx
  /// keeps its remaining attempts.
  Future<void> flushQueue() async {
    if (_flushing) return;
    if (await isOffline) return;
    _flushing = true;
    var changed = false;

    try {
      final pending = await _db.listMutations();
      for (final mutation in pending) {
        try {
          var body = mutation.body;
          if (mutation.hasAttachment) {
            final uploadedUrl = await uploadBytes(
              bytes: mutation.attachment!,
              fileName: mutation.attachmentName ?? 'attachment',
              field: mutation.attachmentField!,
            );
            body = _substitute(body, mutation.placeholder, uploadedUrl);
          }
          await _api.request(
            mutation.method,
            mutation.url,
            data: body,
            mutationId: mutation.clientMutationId,
          );
          await _db.deleteMutation(mutation.clientMutationId);
          changed = true;
        } on NetworkFailure {
          break;
        } on HttpFailure catch (e) {
          final attempts = mutation.attempts + 1;
          final drop = attempts >= Env.maxMutationAttempts ||
              (e.status >= 400 && e.status < 500);
          if (drop) {
            await _db.addConflict(
              label: mutation.label,
              url: mutation.url,
              reason: '${e.status}: ${e.message}',
            );
            await _db.deleteMutation(mutation.clientMutationId);
          } else {
            await _db.bumpAttempts(mutation.clientMutationId, attempts);
          }
          changed = true;
        }
      }
    } finally {
      _flushing = false;
      if (changed) _bus.notify();
    }
  }

  Future<String> uploadBytes({
    required Uint8List bytes,
    required String fileName,
    String field = 'file',
    String? entityType,
    String? entityId,
  }) async {
    final path = field == 'image' ? '/api/upload/image' : '/api/upload/file';
    final form = FormData.fromMap({
      field: MultipartFile.fromBytes(bytes, filename: fileName),
      'entityType': ?entityType,
      'entityId': ?entityId,
    });
    final response = await _api.post(
      path,
      data: form,
      receiveTimeout: Env.uploadTimeout,
    );
    final body = response.data;
    final url = body is Map
        ? (body['data'] is Map ? body['data']['url'] : body['url'])
        : null;
    if (url is! String || url.isEmpty) {
      throw const UnknownFailure('Upload did not return a URL');
    }
    return url;
  }

  dynamic _substitute(dynamic body, String? placeholder, String url) {
    if (placeholder == null || body == null) return body;
    final encoded = jsonEncode(body).replaceAll(placeholder, url);
    return jsonDecode(encoded);
  }
}
