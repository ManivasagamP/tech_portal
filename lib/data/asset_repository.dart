import '../core/network/envelope.dart';
import '../core/offline/sync_client.dart';

class AssetRecordPage {
  const AssetRecordPage({required this.asset, required this.fromCache});

  final Map<String, dynamic> asset;
  final bool fromCache;
}

/// FR-2 — the full asset record, for the detail screen's fallback when
/// there is no c2o scan cache entry to read from (reached via FR-1.6
/// search rather than a scan). The work-order payload FR-1.6 already has in
/// hand only embeds a thin asset sub-object (name and little else); this is
/// the same endpoint the web asset page itself reads, and has everything —
/// manufacturer, model, serial, warranty, condition, description.
class AssetRepository {
  AssetRepository(this._sync);

  final SyncClient _sync;

  /// Offline-first via [SyncClient.syncGet], same pattern as every other
  /// read in this app — cached once opened, so re-opening the same asset
  /// later works with the radio off too.
  Future<AssetRecordPage> get(String assetId) async {
    final read = await _sync.syncGet('/api/fm/assets/$assetId');
    return AssetRecordPage(
      asset: unwrapMap(read.data),
      fromCache: read.fromCache,
    );
  }
}
