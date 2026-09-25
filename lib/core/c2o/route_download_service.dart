import '../../data/route_pack_repository.dart';
import '../offline/offline_db.dart';
import 'route_pack.dart';

/// FR-5.1 — downloads a route pack and writes it into local storage:
/// [DownloadedRoutePack] for the route's own identity/freshness, and each
/// asset upserted into the SAME cache FR-1.1's single-scan resolve already
/// writes to ([C2oAssetCache]) — so a scan during the walk answers offline
/// exactly the way it already does today, whether the asset got there one
/// at a time or in bulk.
///
/// Takes [RouteFetcher]/[C2oAssetCache]/[RoutePackStore] as interfaces
/// (same split as `C2oAssetResolver`) so this is fully testable without
/// sqflite or Dio.
class RouteDownloadService {
  RouteDownloadService({
    required RouteFetcher fetcher,
    required C2oAssetCache assetCache,
    required RoutePackStore routeStore,
  }) : _fetcher = fetcher,
       _assetCache = assetCache,
       _routeStore = routeStore;

  final RouteFetcher _fetcher;
  final C2oAssetCache _assetCache;
  final RoutePackStore _routeStore;

  /// FR-5.1's pre-download size check.
  Future<RoutePackEstimate> estimate({
    required RouteScope scope,
    required String id,
    String? packageId,
    String? projectId,
  }) async {
    final json = await _fetcher.fetchRouteEstimate(
      scope.apiValue,
      id,
      packageId: packageId,
      projectId: projectId,
    );
    return RoutePackEstimate.fromJson(json);
  }

  /// Downloads the pack and persists it — every asset upserted into the
  /// shared c2o cache (stamped with the pack's `versionTag` so it's
  /// identifiable as part of this route later), then the route's own
  /// metadata row. Returns the parsed pack for the screen to show
  /// immediately, without a re-read from disk.
  Future<RoutePack> download({
    required RouteScope scope,
    required String id,
    String? packageId,
    String? projectId,
  }) async {
    final json = await _fetcher.fetchRoutePack(
      scope.apiValue,
      id,
      packageId: packageId,
      projectId: projectId,
    );
    final pack = RoutePack.fromJson(json);

    for (final asset in pack.assets) {
      await _assetCache.upsertC2oAsset(
        CachedC2oAsset(
          assetId: asset.id,
          assetReferenceId: asset.assetReferenceId,
          scanToken: asset.scanToken,
          // Same wrapper shape `resolveScan()` returns — `AssetDetail.fromClaims`
          // reads `claims['asset']` and doesn't care how it got there.
          claims: {
            'asset': asset.raw,
            'history': asset.lastVerificationResult == null
                ? const []
                : [
                    {'result': asset.lastVerificationResult},
                  ],
            'openFindings': const [],
          },
          cachedAt: DateTime.now(),
          packStamp: pack.versionTag,
        ),
      );
    }

    await _routeStore.saveRoutePack(
      DownloadedRoutePack(
        scope: scope,
        id: id,
        asOf: pack.asOf,
        versionTag: pack.versionTag,
        assetIds: pack.assets.map((a) => a.id).toList(),
        downloadedAt: DateTime.now(),
        packageId: packageId,
        projectId: projectId,
      ),
    );

    return pack;
  }

  Future<List<DownloadedRoutePack>> listDownloaded() => _routeStore.listRoutePacks();

  Future<void> delete(RouteScope scope, String id) =>
      _routeStore.deleteRoutePack(scope, id);

  /// FR-5.7 — a pack older than [maxAge] should be refreshed before it's
  /// relied on to verify against. No server-side enforcement of this
  /// threshold (SR-2 only gives the freshness stamp); it's a client policy,
  /// kept here rather than scattered across widgets.
  static bool isStale(DownloadedRoutePack pack, {Duration maxAge = const Duration(hours: 24)}) =>
      pack.age > maxAge;
}

/// Narrow view of [RouteFetcher] this service needs — named separately so
/// the import doesn't force every caller through `data/route_pack_repository.dart`.
abstract interface class RouteFetcherLike {
  Future<Map<String, dynamic>> fetchRouteEstimate(
    String scope,
    String id, {
    String? packageId,
    String? projectId,
  });

  Future<Map<String, dynamic>> fetchRoutePack(
    String scope,
    String id, {
    String? packageId,
    String? projectId,
  });
}
