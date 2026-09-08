import '../core/network/api_client.dart';
import '../core/network/envelope.dart';
import '../core/offline/sync_client.dart';
import '../domain/downtime.dart';
import '../domain/maintenance_record.dart';

class CloseRepository {
  CloseRepository(this._api, this._sync);

  /// The downtime history is read with the plain client rather than `syncGet`:
  /// it only pre-fills the form, and a stale cached window would lock the start
  /// field to a time that is no longer true.
  final ApiClient _api;
  final SyncClient _sync;

  /// Every window recorded against this asset, across all four maintenance
  /// kinds. Returns empty rather than throwing — the close must stay possible
  /// when this lookup fails, exactly as the web's `.catch` allows.
  Future<List<DowntimeWindow>> downtimeHistory(String assetId) async {
    try {
      final response = await _api.get('/api/fm/assets/$assetId/downtime');
      final rows = unwrapMap(response.data)['history'];
      if (rows is! List) return const [];
      return rows
          .whereType<Map>()
          .map((row) => DowntimeWindow.fromJson(Map<String, dynamic>.from(row)))
          .whereType<DowntimeWindow>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Step 1. Written ahead of the close so the server's re-check of the stored
  /// row in step 3 already sees it.
  Future<SyncedWrite> submitRca(
    OrderType type,
    String recordId, {
    String? rootCause,
    String? rcaNotes,
  }) => _sync.syncRequest(
    'post',
    '/api/fm/${type.rcaPath}/$recordId/rca',
    data: {
      if (rootCause != null && rootCause.isNotEmpty) 'rootCause': rootCause,
      if (rcaNotes != null && rcaNotes.isNotEmpty) 'rcaNotes': rcaNotes,
    },
    label: 'Root cause',
    entityType: type.name,
    entityId: recordId,
  );

  /// Step 2. One idempotent PATCH carrying start, end and impact — downtime
  /// lives in three columns on the record itself, so there is no log row to
  /// open and then close.
  Future<SyncedWrite> patchDowntime(
    OrderType type,
    String recordId, {
    required DateTime startedAt,
    required DateTime endedAt,
    required DowntimeImpact impact,
  }) => _sync.syncRequest(
    'patch',
    '/api/fm/downtime/${type.downtimePath}/$recordId',
    data: {
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt.toUtc().toIso8601String(),
      'impact': impact.wire,
    },
    label: 'Downtime',
    entityType: type.name,
    entityId: recordId,
  );

  /// Did the record actually end up closed? Asked after a 5xx on the closing
  /// call, because `workOrderController.ts` completes the work order and only
  /// then throws on a line that references an undefined `status` — the write
  /// has already committed by the time the 500 reaches us.
  Future<bool> isCompleted(OrderType type, String recordId) async {
    try {
      final response = await _api.get('/api/fm/${type.entityPath}/$recordId');
      final record = unwrapMap(response.data);
      if (asDate(record['completedDate']) != null) return true;
      final status = record['status']?.toString().toLowerCase().trim();
      return status == 'completed';
    } catch (_) {
      // No answer means no evidence it closed. Report the original failure.
      return false;
    }
  }

  /// Step 3, the call that actually closes the record.
  Future<SyncedWrite> complete(
    OrderType type,
    String recordId, {
    double? actualHours,
    String? rootCause,
  }) => _sync.syncRequest(
    'post',
    '/api/fm/${type.completePath}/$recordId/time-tracking',
    data: {
      'action': 'complete',
      'actualHours': ?actualHours,
      if (rootCause != null && rootCause.isNotEmpty) 'rootCause': rootCause,
    },
    label: 'Close ${type.label.toLowerCase()}',
    entityType: type.name,
    entityId: recordId,
  );
}
