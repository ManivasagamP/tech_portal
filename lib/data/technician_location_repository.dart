import '../core/network/api_client.dart';

class TechnicianLocationRepository {
  TechnicianLocationRepository(this._api);

  final ApiClient _api;

  /// POST /api/fm/technicians/me/location — reports the technician's own
  /// current fix. `technicianId` always comes from the JWT server-side, so
  /// the body carries only lat/lng. Exempt from the location gate itself
  /// (server `middleware/auth.ts`), so this call can always get through even
  /// when every other mutating request is currently being rejected with 428.
  Future<void> updateLocation(double lat, double lng) => _api.post(
        '/api/fm/technicians/me/location',
        data: {'lat': lat, 'lng': lng},
      );
}
