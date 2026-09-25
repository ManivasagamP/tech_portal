import 'asset_detail.dart';

/// FR-5.2 (room-grouped list) / FR-5.3 (verified/outstanding/flagged
/// progress) — pure logic over a downloaded route's cached assets, kept
/// separate from `route_detail_screen.dart` for the same reason
/// `asset_detail.dart` is separate from its screen: testable without
/// Riverpod or a `BuildContext`.

/// One asset in a route's list — a lighter read than [AssetDetail], which
/// also carries twin/OCR fields this view has no use for, built from the
/// same `claims['asset']` shape.
class RouteAssetRow {
  const RouteAssetRow({
    required this.id,
    required this.name,
    required this.roomLabel,
    required this.status,
  });

  final String id;
  final String? name;

  /// Null when the asset carries no Room step in its location walk — the
  /// caller decides what to call that bucket (localization lives with the
  /// widget, not here).
  final String? roomLabel;

  /// "pending" | "verified" | "mismatch" | "missing" — the server's
  /// `assets.c2oVerificationStatus` enum, read straight off the cached claim.
  final String status;

  bool get isVerified => status == 'verified';
  bool get isFlagged => status == 'mismatch' || status == 'missing';
  bool get isOutstanding => !isVerified && !isFlagged;
}

/// Builds a [RouteAssetRow] from a cached c2o asset's `claims` — the same
/// wrapper shape `resolveScan()`/`RouteDownloadService.download` both write,
/// so this reads a scanned-in and a bulk-downloaded asset identically.
RouteAssetRow routeAssetRowFromClaims({
  required String assetId,
  String? assetReferenceId,
  required Map<String, dynamic> claims,
}) {
  final detail = AssetDetail.fromClaims(claims);
  final room = detail?.locationPath
      .where((s) => s.level == 'Room')
      .map((s) => s.code ?? s.label)
      .whereType<String>()
      .firstOrNull;
  final asset = claims['asset'];
  final status = asset is Map ? asset['verificationStatus']?.toString() : null;
  return RouteAssetRow(
    id: assetId,
    name: detail?.assetName ?? assetReferenceId,
    roomLabel: room,
    status: status ?? 'pending',
  );
}

/// FR-5.3 — verified/outstanding/flagged tallies for one route.
class RouteProgress {
  const RouteProgress({
    required this.verified,
    required this.outstanding,
    required this.flagged,
  });

  final int verified;
  final int outstanding;
  final int flagged;

  int get total => verified + outstanding + flagged;

  factory RouteProgress.from(List<RouteAssetRow> rows) => RouteProgress(
    verified: rows.where((r) => r.isVerified).length,
    outstanding: rows.where((r) => r.isOutstanding).length,
    flagged: rows.where((r) => r.isFlagged).length,
  );
}

/// FR-5.2 — assets grouped by room label, [unassignedLabel] standing in for
/// any asset with no Room step at all.
Map<String, List<RouteAssetRow>> groupRouteAssetsByRoom(
  List<RouteAssetRow> rows, {
  required String unassignedLabel,
}) {
  final byRoom = <String, List<RouteAssetRow>>{};
  for (final row in rows) {
    byRoom.putIfAbsent(row.roomLabel ?? unassignedLabel, () => []).add(row);
  }
  return byRoom;
}

/// Room names in walk order — alphabetical, [unassignedLabel] always last
/// regardless of where it would otherwise sort (it isn't a real room; it
/// shouldn't look like the first stop on the walk).
List<String> sortRoomNames(Iterable<String> names, {required String unassignedLabel}) {
  final sorted = names.toList()
    ..sort((a, b) {
      if (a == unassignedLabel) return 1;
      if (b == unassignedLabel) return -1;
      return a.compareTo(b);
    });
  return sorted;
}
