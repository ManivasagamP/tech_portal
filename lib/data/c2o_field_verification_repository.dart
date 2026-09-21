import '../core/network/api_client.dart';

/// The one c2o operation `C2oAssetResolver` needs, pulled out of
/// [C2oFieldVerificationRepository] so a test can fake it without a network.
abstract interface class C2oScanFetcher {
  Future<Map<String, dynamic>> fetchScanTarget(String assetId, String? token);
}

/// Wraps the one unauthenticated route in the API — the tag itself is the
/// credential. See `resolveScan()` in the server's `fieldVerificationService`.
class C2oFieldVerificationRepository implements C2oScanFetcher {
  C2oFieldVerificationRepository(this._api);

  final ApiClient _api;

  /// GET /api/c2o/public/verify/:assetId?t= — throws [HttpFailure] with
  /// status 403 for a bad/mismatched token, 404 for an unknown asset id, or
  /// [NetworkFailure] with no signal at all (see `ApiClient._run`).
  @override
  Future<Map<String, dynamic>> fetchScanTarget(
    String assetId,
    String? token,
  ) async {
    final response = await _api.get(
      '/api/c2o/public/verify/$assetId',
      query: token == null ? null : {'t': token},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
