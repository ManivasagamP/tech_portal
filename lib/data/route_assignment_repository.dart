import '../core/c2o/assigned_route.dart';
import '../core/network/api_client.dart';
import '../core/offline/sync_client.dart';

typedef AssignedRoutesRead = ({List<AssignedRoute> routes, bool fromCache});

/// FR-5.5 — the signed-in technician's assigned routes. Read through
/// [SyncClient.syncGet] so the last list loaded is still there underground,
/// flagged `fromCache` so the screen can say it may be out of date.
class RouteAssignmentRepository {
  RouteAssignmentRepository(this._sync, this._api);

  final SyncClient _sync;
  final ApiClient _api;

  Future<AssignedRoutesRead> fetchMine() async {
    final read = await _sync.syncGet('/api/c2o/route-assignments/mine');
    return (routes: parseAssignedRoutes(read.data), fromCache: read.fromCache);
  }

  /// FR-5.8 — give the route back so an admin can reassign it. Deliberately
  /// NOT queued: it's a hand-over decision the admin acts on, and a release
  /// that silently lands hours later would leave the route unwalked with
  /// nobody told. Offline, this throws [NetworkFailure] and the screen says
  /// so; the technician's own checks still queue and upload as normal.
  Future<void> release(String assignmentId, {String? note}) async {
    final trimmed = note?.trim();
    await _api.post(
      '/api/c2o/route-assignments/$assignmentId/release',
      data: {if (trimmed != null && trimmed.isNotEmpty) 'note': trimmed},
    );
  }
}
