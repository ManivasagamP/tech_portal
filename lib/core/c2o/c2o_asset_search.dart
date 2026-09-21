import '../offline/offline_db.dart';

/// FR-1.6 — manual search over today's downloaded route, entirely on-device.
/// This is the fallback for a missing/unreadable tag, so it must never touch
/// the network: everything it searches is already in [CachedC2oAsset.claims]
/// from FR-1.1's cache. An empty query returns the whole route, so this
/// screen doubles as a plain browse when nothing's actually being searched.
List<CachedC2oAsset> searchCachedAssets(List<CachedC2oAsset> assets, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return assets;
  return assets.where((asset) => _matches(asset, q)).toList();
}

bool _matches(CachedC2oAsset cached, String query) {
  final asset = cached.claims['asset'];
  final fields = <String?>[
    cached.assetId,
    cached.assetReferenceId,
    if (asset is Map) ...[
      asset['assetName']?.toString(),
      asset['serialNumber']?.toString(),
      asset['supplierTagNumber']?.toString(),
      // "Room" per FR-1.6 — the flat location fields `resolveScan()`
      // returns alongside the structured `locationPath`.
      asset['space']?.toString(),
      asset['building']?.toString(),
      asset['floor']?.toString(),
      asset['location']?.toString(),
    ],
  ];
  return fields.any((field) => field != null && field.toLowerCase().contains(query));
}
