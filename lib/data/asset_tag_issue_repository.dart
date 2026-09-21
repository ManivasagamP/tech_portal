import '../core/offline/offline_db.dart';
import '../core/offline/sync_client.dart';

/// Sends the FR-1.7 tag-missing/unreadable report to the server, so it
/// actually reaches an admin — the local [TagIssueLog] table alone is just
/// on-device evidence and was never wired to anything. Queues offline like
/// any other mutation, so a report filed with no signal is not lost.
class AssetTagIssueRepository {
  AssetTagIssueRepository(this._sync);

  final SyncClient _sync;

  Future<SyncedWrite> report(
    String assetId, {
    required TagIssueReason reason,
    String? note,
  }) => _sync.syncRequest(
    'post',
    '/api/fm/assets/$assetId/tag-issue',
    data: {'reason': reason.name, 'note': ?note},
    label: 'Report tag issue',
    entityType: 'Asset',
    entityId: assetId,
  );
}
