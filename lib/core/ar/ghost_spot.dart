import 'dart:math' as math;

import '../../domain/ar_models.dart' show FloorPlan, ManifestMarker, PlanSpace, pointInPolygon;
import 'corner_matcher.dart';
import 'coverage.dart';
import 'vec.dart';

/// A suggested spot for a spare board: "Stick a spare board here"
/// (docs/ar-setup-and-gamma-parity.md §2.5, S4Locked).
class GhostSpot {
  const GhostSpot({
    required this.posTile,
    required this.normalTile,
    required this.cornerId,
    required this.cornerLabel,
    required this.offsetM,
    required this.score,
    required this.coverageBefore,
    required this.coverageAfter,
    this.distanceToCameraM,
    this.structural = false,
  });

  /// Board centre, tile frame (1.5 m above the finished floor).
  final Vec3 posTile;

  /// The wall's facing, horizontal, tile frame.
  final Vec3 normalTile;

  /// The corner whose wall the spot is on, and how far along it.
  final String cornerId;
  final String cornerLabel;
  final double offsetM;

  final double score;

  /// Predicted coverage share (cells ≤ 10 cm) around the user, before and
  /// after a Derived board here — the same model as the web heatmap.
  final double coverageBefore;
  final double coverageAfter;
  final double? distanceToCameraM;
  final bool structural;

  double get coverageGain => coverageAfter - coverageBefore;
}

/// Chooses where a spare board would help most, from what a floor pack
/// already carries: corner candidates (their faces are flat wall known to be
/// at least 0.4 m wide), existing boards, and — when the plan was fetched —
/// doors and equipment to keep clear of.
///
/// Candidates sit on each corner's two walls, [offsetsM] along from the
/// corner, at [centreHeightM]. They are scored by the coverage they add
/// around the user (the C3 model with the new board as Derived), how close
/// they are to where the user stands (they'll stick it up now), structure
/// (drywall moves in a fit-out), and being near a door (seen on the way in).
class GhostSpotFinder {
  const GhostSpotFinder({
    this.centreHeightM = 1.5,
    this.offsetsM = const [0.8, 1.2],
    this.minBoardSpacingM = 2.0,
    this.doorClearanceM = 0.9,
    this.equipmentClearanceM = 0.4,
    this.sampleRadiusM = 10,
    this.cellM = 1.0,
  });

  final double centreHeightM;
  final List<double> offsetsM;
  final double minBoardSpacingM;
  final double doorClearanceM;
  final double equipmentClearanceM;
  final double sampleRadiusM;
  final double cellM;

  /// Up to [limit] spots, best first, at least [minBoardSpacingM] apart.
  List<GhostSpot> suggest({
    required List<CornerCandidate> corners,
    List<ManifestMarker> markers = const [],
    Vec3? cameraTile,
    double floorFinishOffsetM = 0,
    FloorPlan? plan,
    int limit = 3,
  }) {
    final scored = _scored(
      corners: corners,
      markers: markers,
      cameraTile: cameraTile,
      floorFinishOffsetM: floorFinishOffsetM,
      plan: plan,
    );
    final picked = <GhostSpot>[];
    for (final s in scored) {
      if (picked.length >= limit) break;
      if (picked.any((p) => p.posTile.distanceXzTo(s.posTile) < minBoardSpacingM)) continue;
      picked.add(s);
    }
    return picked;
  }

  /// Every usable spot, scored, best first (no spacing between them).
  List<GhostSpot> _scored({
    required List<CornerCandidate> corners,
    required List<ManifestMarker> markers,
    required Vec3? cameraTile,
    required double floorFinishOffsetM,
    required FloorPlan? plan,
  }) {
    if (corners.isEmpty) return const [];
    final centre = cameraTile?.xz ?? _centroid(corners);
    final cells = _cells(centre, plan);
    final existing = [
      for (final m in markers)
        CoverageMarker(x: m.posTile.x, z: m.posTile.z, accuracyClass: m.accuracyClass),
    ];
    final before = ArCoverage.coverageShare(existing, cells);

    final scored = <GhostSpot>[];
    for (final spot in _candidates(corners, floorFinishOffsetM, plan)) {
      if (_tooCloseToBoards(spot.pos, markers)) continue;
      final after = ArCoverage.coverageShare(
        [...existing, CoverageMarker(x: spot.pos.x, z: spot.pos.z, accuracyClass: 'derived')],
        cells,
      );
      final toCamera = cameraTile?.distanceXzTo(spot.pos);
      final proximity = toCamera == null ? 0.5 : math.max(0.0, 1 - (toCamera - 3).abs() / 6);
      final entrance = plan == null ? 0.0 : _nearDoorScore(spot.pos.xz, plan);
      final score = 0.55 * (after - before) +
          0.25 * proximity +
          (spot.corner.structural ? 0.12 : 0.0) +
          0.08 * entrance;
      scored.add(GhostSpot(
        posTile: spot.pos,
        normalTile: Vec3(spot.normal.x, 0, spot.normal.y),
        cornerId: spot.corner.id,
        cornerLabel: spot.corner.label,
        offsetM: spot.offset,
        score: score,
        coverageBefore: before,
        coverageAfter: after,
        distanceToCameraM: toCamera,
        structural: spot.corner.structural,
      ));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  /// The single best spot, or null when the pack has no usable wall.
  GhostSpot? best({
    required List<CornerCandidate> corners,
    List<ManifestMarker> markers = const [],
    Vec3? cameraTile,
    double floorFinishOffsetM = 0,
    FloorPlan? plan,
  }) {
    final spots = suggest(
      corners: corners,
      markers: markers,
      cameraTile: cameraTile,
      floorFinishOffsetM: floorFinishOffsetM,
      plan: plan,
      limit: 1,
    );
    return spots.isEmpty ? null : spots.first;
  }

  /// A second board for a two-board lock, 3–10 m from [first], scored with
  /// [first] already counted as a board: on a wall facing it (normals at
  /// least 120° apart) when there is one in range, otherwise on an adjacent
  /// wall (roughly perpendicular) — "mount markers in pairs, on facing or
  /// adjacent walls" (docs/ar-bim-overlay.md §4.4). Never on the same wall:
  /// two boards side by side add almost no heading information.
  GhostSpot? pairFor(
    GhostSpot first, {
    required List<CornerCandidate> corners,
    List<ManifestMarker> markers = const [],
    double floorFinishOffsetM = 0,
    FloorPlan? plan,
  }) {
    final withFirst = [
      ...markers,
      ManifestMarker(
        code: 'GHOST00',
        label: '',
        status: 'planned',
        accuracyClass: 'derived',
        mounting: 'wall',
        posTile: first.posTile,
        normalTile: first.normalTile,
        sigmaM: 0.03,
      ),
    ];
    // Every candidate, not [suggest]'s spaced shortlist: a strong spot on
    // the first board's own wall must not hide the adjacent-wall ones.
    final spots = _scored(
      corners: corners,
      markers: withFirst,
      cameraTile: first.posTile,
      floorFinishOffsetM: floorFinishOffsetM,
      plan: plan,
    );
    bool inRange(GhostSpot s) {
      final d = s.posTile.distanceXzTo(first.posTile);
      return d >= 3 && d <= 10;
    }

    for (final s in spots) {
      if (inRange(s) && s.normalTile.dot(first.normalTile) <= -0.5) return s;
    }
    for (final s in spots) {
      if (inRange(s) && s.normalTile.dot(first.normalTile).abs() <= 0.5) return s;
    }
    return null;
  }

  Iterable<_Candidate> _candidates(
    List<CornerCandidate> corners,
    double finishOffset,
    FloorPlan? plan,
  ) sync* {
    for (final c in corners) {
      final nA = c.faceA.normalized;
      final nB = c.faceB.normalized;
      if (nA.length == 0 || nB.length == 0) continue;
      // Column faces are rarely wide enough for a 210 mm board.
      if (c.kind == 'column') continue;
      final inside = c.kind == 'inside';
      for (final (normal, other) in [(nA, nB), (nB, nA)]) {
        // Along the wall, away from the corner: toward the other face's
        // normal on an inside corner, away from it on an outside corner.
        var along = Vec2(-normal.y, normal.x);
        final towardOther = along.dot(other) > 0;
        if (inside != towardOther) along = -along;
        for (final offset in offsetsM) {
          final xz = c.posTile.xz + along * offset;
          final pos = Vec3(xz.x, c.posTile.y + finishOffset + centreHeightM, xz.y);
          if (plan != null && !_clearOnPlan(xz, plan)) continue;
          yield _Candidate(corner: c, pos: pos, normal: normal, offset: offset);
        }
      }
    }
  }

  bool _tooCloseToBoards(Vec3 p, List<ManifestMarker> markers) =>
      markers.any((m) => m.posTile.distanceXzTo(p) < minBoardSpacingM);

  bool _clearOnPlan(Vec2 p, FloorPlan plan) {
    for (final o in plan.openings) {
      if (o.kind == 'door' && _distToSegment(p, o.a, o.b) < doorClearanceM) return false;
    }
    for (final e in plan.equipment) {
      if (pointInPolygon(p.x, p.y, e.polygon)) return false;
      if (_distToPolyline(p, e.polygon, closed: true) < equipmentClearanceM) return false;
    }
    if (plan.walls.isNotEmpty) {
      // The spot must actually be on a modelled wall face.
      final onWall = plan.walls.any(
        (w) => _distToPolyline(p, w.polyline) <= w.thickness / 2 + 0.15,
      );
      if (!onWall) return false;
    }
    return true;
  }

  /// 1 when a door is 1.5–3 m away (seen on the way in, clear of its swing),
  /// fading to 0 by 6 m.
  double _nearDoorScore(Vec2 p, FloorPlan plan) {
    var best = 0.0;
    for (final o in plan.openings) {
      if (o.kind != 'door') continue;
      final d = _distToSegment(p, o.a, o.b);
      final s = d < 1.5 ? d / 1.5 : (d <= 3 ? 1.0 : math.max(0.0, 1 - (d - 3) / 3));
      best = math.max(best, s);
    }
    return best;
  }

  List<(double, double)> _cells(Vec2 centre, FloorPlan? plan) {
    final PlanSpace? space = plan?.spaceAt(centre.x, centre.y);
    final out = <(double, double)>[];
    final r = sampleRadiusM;
    final steps = (r / cellM).floor();
    for (var i = -steps; i <= steps; i++) {
      for (var j = -steps; j <= steps; j++) {
        final dx = i * cellM;
        final dz = j * cellM;
        if (dx * dx + dz * dz > r * r) continue;
        final x = centre.x + dx;
        final z = centre.y + dz;
        if (space != null && !pointInPolygon(x, z, space.polygon)) continue;
        out.add((x, z));
      }
    }
    return out;
  }

  static Vec2 _centroid(List<CornerCandidate> corners) {
    var sum = Vec2.zero;
    for (final c in corners) {
      sum = sum + c.posTile.xz;
    }
    return sum * (1 / corners.length);
  }

  static double _distToSegment(Vec2 p, Vec2 a, Vec2 b) {
    final ab = b - a;
    final len2 = ab.dot(ab);
    if (len2 < 1e-12) return p.distanceTo(a);
    final t = math.max(0.0, math.min(1.0, (p - a).dot(ab) / len2));
    return p.distanceTo(a + ab * t);
  }

  static double _distToPolyline(Vec2 p, List<Vec2> pts, {bool closed = false}) {
    if (pts.isEmpty) return double.infinity;
    if (pts.length == 1) return p.distanceTo(pts.first);
    var best = double.infinity;
    for (var i = 0; i < pts.length - 1; i++) {
      best = math.min(best, _distToSegment(p, pts[i], pts[i + 1]));
    }
    if (closed) best = math.min(best, _distToSegment(p, pts.last, pts.first));
    return best;
  }
}

class _Candidate {
  const _Candidate({
    required this.corner,
    required this.pos,
    required this.normal,
    required this.offset,
  });

  final CornerCandidate corner;
  final Vec3 pos;
  final Vec2 normal;
  final double offset;
}
