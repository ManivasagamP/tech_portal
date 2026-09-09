import '../core/network/envelope.dart';
import '../core/offline/sync_client.dart';
import '../domain/asset_document.dart';

class AssetDocumentsPage {
  const AssetDocumentsPage({required this.documents, required this.fromCache});

  final List<AssetDocument> documents;
  final bool fromCache;
}

/// Documents attached to an asset — Warranty / O&M / Datasheet / Certificates
/// etc. Read-only from this app: technicians view and open what has already
/// been attached from the web/admin side, so there is no add/delete here even
/// though the server exposes those endpoints too.
class AssetDocumentsRepository {
  AssetDocumentsRepository(this._sync);

  final SyncClient _sync;

  /// Goes through [SyncClient.syncGet] so the list is available offline from
  /// cache — the same pattern the order list and order detail use. Newest
  /// first, already sorted by the server.
  Future<AssetDocumentsPage> list(String assetId) async {
    final read = await _sync.syncGet('/api/fm/assets/$assetId/documents');
    return AssetDocumentsPage(
      documents: AssetDocument.listFrom(unwrapList(read.data)),
      fromCache: read.fromCache,
    );
  }
}
