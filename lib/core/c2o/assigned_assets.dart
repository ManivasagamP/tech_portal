import '../../domain/maintenance_record.dart';
import '../offline/offline_db.dart';

/// FR-1.6 scoping — before this, manual search only covered [CachedC2oAsset]
/// rows already sitting in the FR-1.1 scan cache, i.e. only assets a
/// technician had *already* pointed a camera at. That is backwards for the
/// no-tag-to-scan case search exists for: it should start from the assets
/// actually assigned to this technician today, scanned or not.
///
/// This turns the technician's assigned work orders (already fetched
/// offline-first via `OrdersRepository.listAll`) into entries shaped like
/// [CachedC2oAsset] so [searchCachedAssets] can search both sources with one
/// matcher. The work-order asset sub-object is a different wire shape than
/// c2o's `resolveScan()` claims — the only field `MaintenanceRecord` itself
/// relies on is `name` (see `MaintenanceRecord.assetName`) — so every field
/// here is read through a fallback chain rather than assumed to exist.
List<CachedC2oAsset> assignedAssetsFrom(List<MaintenanceRecord> records) {
  final byId = <String, CachedC2oAsset>{};
  for (final record in records) {
    final assetId = record.assetId;
    if (assetId == null || assetId.isEmpty) continue;

    final rawAsset = record.raw['asset'];
    final asset = rawAsset is Map ? Map<String, dynamic>.from(rawAsset) : const <String, dynamic>{};

    byId[assetId] = CachedC2oAsset(
      assetId: assetId,
      assetReferenceId: _firstString([
        asset['supplierTagNumber'],
        asset['assetReferenceId'],
        asset['tagNumber'],
        record.referenceId,
      ]),
      claims: {
        'asset': {
          'assetName': _firstString([asset['assetName'], asset['name'], record.assetName]),
          'manufacturer': asset['manufacturer']?.toString(),
          'model': asset['model']?.toString(),
          'serialNumber': _firstString([asset['serialNumber'], asset['serial']]),
          'supplierTagNumber': _firstString([asset['supplierTagNumber'], asset['tagNumber']]),
          'space': _firstString([asset['space'], record.location]),
          'building': asset['building']?.toString(),
          'floor': asset['floor']?.toString(),
          'location': _firstString([asset['location'], record.location]),
        },
      },
      cachedAt: DateTime.now(),
    );
  }
  return byId.values.toList();
}

String? _firstString(List<dynamic> values) {
  for (final value in values) {
    final s = value?.toString();
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}
