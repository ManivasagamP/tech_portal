import '../offline/offline_db.dart' show DownloadedRoutePack, PendingMutation;
import 'route_pack.dart';

/// FR-5.5 — a route an admin assigned to this technician, as returned by
/// `GET /api/c2o/route-assignments/mine`. Answers "what's waiting for me"
/// without anyone having to pass a route id around out of band.
///
/// [scope] + [scopeId] (+ anchors) are exactly what the Download flow sends
/// to `GET /api/c2o/routes/:scope`, so an assigned route downloads through the
/// same path as a manually entered one.
class AssignedRoute {
  const AssignedRoute({
    required this.id,
    required this.scope,
    required this.scopeId,
    required this.label,
    required this.assignedAt,
    this.packageId,
    this.projectId,
    this.assetCount,
    this.checkedCount,
    this.handedOverFromName,
  });

  final String id;
  final RouteScope scope;
  final String scopeId;
  final String? packageId;
  final String? projectId;

  /// Human-readable name from the server (package name, or "Building B1 ·
  /// Tower A") — what the technician reads instead of a uuid.
  final String label;

  /// Null when the server couldn't resolve the route at list time.
  final int? assetCount;

  /// When this technician got it — a reassignment resets it.
  final DateTime assignedAt;

  /// FR-5.8 — assets already checked (verified + flagged) across the whole
  /// route, by anyone, as far as the SERVER knows. Null on an older server.
  final int? checkedCount;

  /// FR-5.8 — set when an admin moved this route from another technician
  /// mid-walk, so "8 of 40 checked" reads as their work, not a mistake.
  final String? handedOverFromName;

  bool get isHandOver => handedOverFromName != null;

  /// Unknown scopes (a newer server) and malformed rows return null rather
  /// than throwing, so one bad row never hides the rest of the list.
  static AssignedRoute? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final scopeId = json['scopeId'];
    final scope = RouteScope.values.asNameMap()[json['scope']];
    if (id is! String || scopeId is! String || scope == null) return null;

    final label = json['label'];
    final count = json['assetCount'];
    final progress = json['progress'];
    int? checked;
    if (progress is Map && progress['verified'] is num && progress['flagged'] is num) {
      checked = (progress['verified'] as num).toInt() + (progress['flagged'] as num).toInt();
    }
    final from = json['handedOverFrom'];
    String? fromName;
    if (from is Map) {
      final name = from['name'];
      // A hand-off from a since-deleted account still reads as a hand-off.
      fromName = name is String && name.trim().isNotEmpty ? name : '—';
    }
    return AssignedRoute(
      id: id,
      scope: scope,
      scopeId: scopeId,
      packageId: json['packageId'] as String?,
      projectId: json['projectId'] as String?,
      label: label is String && label.isNotEmpty ? label : scopeId,
      assetCount: count is num ? count.toInt() : null,
      assignedAt: DateTime.tryParse(json['assignedAt']?.toString() ?? '') ?? DateTime.now(),
      checkedCount: checked,
      handedOverFromName: fromName,
    );
  }

  /// Already on this device? Matched on the same (scope, id) key the
  /// downloaded-routes table uses as its primary key.
  bool isDownloadedIn(Iterable<DownloadedRoutePack> downloaded) =>
      downloaded.any((d) => d.scope == scope && d.id == scopeId);
}

List<AssignedRoute> parseAssignedRoutes(Object? body) {
  if (body is! List) return const [];
  return body.map(AssignedRoute.fromJson).whereType<AssignedRoute>().toList();
}

/// FR-5.8 — checks for this route still sitting in this phone's offline
/// queue. The server can't see these, so only the phone can warn about them
/// before the technician gives the route away. Matched by asset id against
/// the downloaded pack: a check is queued against its asset, not its route
/// (see `FieldVerificationRepository.submit`). No pack on the phone means
/// no way to tell, so 0.
int queuedChecksForRoute(DownloadedRoutePack? pack, Iterable<PendingMutation> queue) {
  if (pack == null) return 0;
  final ids = pack.assetIds.toSet();
  return queue
      .where(
        (m) =>
            m.entityType == 'Asset' &&
            m.entityId != null &&
            ids.contains(m.entityId) &&
            m.url.endsWith('/verify'),
      )
      .length;
}
