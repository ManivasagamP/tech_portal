import '../core/network/api_client.dart';

/// The two route-pack calls `RouteDownloadService` needs, pulled out of
/// [RoutePackRepository] so a test can fake them without a network — same
/// split as `C2oScanFetcher`/`C2oFieldVerificationRepository`.
abstract interface class RouteFetcher {
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

/// Wraps `GET /api/c2o/routes/:scope` (SR-1/SR-2) — authenticated, unlike
/// the public scan pair, since a route pack is downloaded by a signed-in
/// technician against an assigned package/project.
class RoutePackRepository implements RouteFetcher {
  RoutePackRepository(this._api);

  final ApiClient _api;

  Map<String, dynamic> _query(String id, String? packageId, String? projectId) => {
    'id': id,
    'packageId': ?packageId,
    'projectId': ?projectId,
  };

  @override
  Future<Map<String, dynamic>> fetchRouteEstimate(
    String scope,
    String id, {
    String? packageId,
    String? projectId,
  }) async {
    final response = await _api.get(
      '/api/c2o/routes/$scope',
      query: {..._query(id, packageId, projectId), 'estimate': 'true'},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  Future<Map<String, dynamic>> fetchRoutePack(
    String scope,
    String id, {
    String? packageId,
    String? projectId,
  }) async {
    final response = await _api.get(
      '/api/c2o/routes/$scope',
      query: _query(id, packageId, projectId),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
