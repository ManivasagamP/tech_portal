import 'dart:async';

import '../../app/env.dart';
import '../network/envelope.dart';
import 'sync_client.dart';

class PrefetchResult {
  const PrefetchResult({
    this.saved = 0,
    this.failed = 0,
    this.skipped = false,
    this.offline = false,
  });

  final int saved;
  final int failed;
  final bool skipped;
  final bool offline;
}

const _lastPrefetchKey = 'lastPrefetchAt';
const _concurrency = 4;

/// Warms the offline cache from GET /api/sync/manifest. The server returns URLs
/// rather than bodies because the four detail endpoints do not share an envelope.
Future<PrefetchResult> prefetchOfflineBundle(
  SyncClient sync,
  String technicianId, {
  bool force = false,
}) async {
  if (technicianId.isEmpty) return const PrefetchResult(skipped: true);
  if (await sync.isOffline) return const PrefetchResult(offline: true);

  if (!force) {
    final last = await sync.db.readMeta(_lastPrefetchKey);
    final lastAt = last == null ? null : DateTime.tryParse(last);
    if (lastAt != null &&
        DateTime.now().difference(lastAt) < Env.prefetchThrottle) {
      return const PrefetchResult(skipped: true);
    }
  }

  final manifest = await sync.syncGet(
    '/api/sync/manifest',
    query: {'technicianId': technicianId},
  );
  final data = unwrapMap(manifest.data);
  final urls = (data['urls'] as List?)?.whereType<String>().toList() ?? const [];

  var saved = 0;
  var failed = 0;

  for (var i = 0; i < urls.length; i += _concurrency) {
    final batch = urls.skip(i).take(_concurrency);
    await Future.wait(
      batch.map((url) async {
        try {
          await sync.syncGet(url);
          saved++;
        } catch (_) {
          failed++;
        }
      }),
    );
  }

  await sync.db.writeMeta(_lastPrefetchKey, DateTime.now().toIso8601String());
  return PrefetchResult(saved: saved, failed: failed);
}
