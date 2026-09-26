import 'dart:math' as math;

import '../ar/vec.dart';

/// Pure maths behind the model viewer's 2D plan (docs/bim-viewer.md §5):
/// the pan/zoom viewport, hit tests and the split view's view cone. No
/// Flutter types, so it is tested on any Dart SDK; the widget converts
/// `Offset` ↔ [Vec2] at the edge.
///
/// Plan coordinates are the tile frame's XZ in metres (x right, z down, like
/// the web plan). Screen coordinates are logical pixels from the top-left.

/// Maps plan metres to screen pixels: `screen = plan * scale + offset`.
/// No rotation — north stays where the model put it, as on the web plan and
/// the printed placement maps.
class PlanViewport {
  const PlanViewport({required this.scale, required this.offset});

  /// Pixels per metre.
  final double scale;
  final Vec2 offset;

  static const minScale = 1.0; // 1 px per metre: a 400 m site on a phone
  static const maxScale = 400.0; // 400 px per metre: a valve handle

  /// Fit `[minX, minZ, maxX, maxZ]` into a `width × height` view with
  /// [padding] pixels all round, centred.
  factory PlanViewport.fit(List<double> bounds, double width, double height, {double padding = 24}) {
    final bw = math.max(0.5, bounds[2] - bounds[0]);
    final bh = math.max(0.5, bounds[3] - bounds[1]);
    final w = math.max(1.0, width - 2 * padding);
    final h = math.max(1.0, height - 2 * padding);
    final s = math.min(w / bw, h / bh).clamp(minScale, maxScale).toDouble();
    final cx = (bounds[0] + bounds[2]) / 2;
    final cz = (bounds[1] + bounds[3]) / 2;
    return PlanViewport(scale: s, offset: Vec2(width / 2 - cx * s, height / 2 - cz * s));
  }

  Vec2 toScreen(Vec2 plan) => Vec2(plan.x * scale + offset.x, plan.y * scale + offset.y);

  Vec2 toPlan(Vec2 screen) => Vec2((screen.x - offset.x) / scale, (screen.y - offset.y) / scale);

  PlanViewport panBy(Vec2 deltaPx) => PlanViewport(scale: scale, offset: offset + deltaPx);

  /// Zoom by [factor] keeping the plan point under [focalPx] fixed on screen.
  PlanViewport zoomAbout(Vec2 focalPx, double factor) {
    final next = (scale * factor).clamp(minScale, maxScale).toDouble();
    final k = next / scale;
    return PlanViewport(
      scale: next,
      offset: Vec2(focalPx.x - (focalPx.x - offset.x) * k, focalPx.y - (focalPx.y - offset.y) * k),
    );
  }

  /// Pan so [plan] sits at the centre of a `width × height` view.
  PlanViewport centreOn(Vec2 plan, double width, double height) =>
      PlanViewport(scale: scale, offset: Vec2(width / 2 - plan.x * scale, height / 2 - plan.y * scale));

  /// Whether [plan] is within [marginPx] of the view's edges (so "follow
  /// the walker" only re-centres when the dot is about to leave).
  bool shows(Vec2 plan, double width, double height, {double marginPx = 32}) {
    final s = toScreen(plan);
    return s.x >= marginPx && s.y >= marginPx && s.x <= width - marginPx && s.y <= height - marginPx;
  }

  @override
  bool operator ==(Object other) => other is PlanViewport && other.scale == scale && other.offset == offset;

  @override
  int get hashCode => Object.hash(scale, offset);
}

/// Even-odd point-in-polygon on the plan.
bool pointInPolygon(List<Vec2> poly, Vec2 p) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i];
    final b = poly[j];
    if ((a.y > p.y) != (b.y > p.y)) {
      final dz = b.y - a.y;
      final xCross = (b.x - a.x) * (p.y - a.y) / (dz == 0 ? 1e-12 : dz) + a.x;
      if (p.x < xCross) inside = !inside;
    }
  }
  return inside;
}

/// Distance from [p] to the segment a–b.
double distanceToSegment(Vec2 p, Vec2 a, Vec2 b) {
  final ab = b - a;
  final len2 = ab.dot(ab);
  if (len2 < 1e-18) return p.distanceTo(a);
  final t = ((p - a).dot(ab) / len2).clamp(0.0, 1.0).toDouble();
  return p.distanceTo(a + ab * t);
}

/// Distance from [p] to a polygon's outline; 0 inside it.
double distanceToPolygon(List<Vec2> poly, Vec2 p) {
  if (poly.isEmpty) return double.infinity;
  if (poly.length >= 3 && pointInPolygon(poly, p)) return 0;
  var best = double.infinity;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    best = math.min(best, distanceToSegment(p, a, b));
  }
  return best;
}

/// The index of the polygon a tap at [p] means: one containing it (the
/// smallest, so a pump inside a plant-room outline wins), else the nearest
/// within [toleranceM]. Null when nothing is close. A finger is ~9 mm wide,
/// so callers pass `toleranceM = 20 px / scale`.
int? hitPolygon(List<List<Vec2>> polys, Vec2 p, double toleranceM) {
  int? best;
  var bestArea = double.infinity;
  for (var i = 0; i < polys.length; i++) {
    final poly = polys[i];
    if (poly.length >= 3 && pointInPolygon(poly, p)) {
      final area = polygonArea(poly).abs();
      if (area < bestArea) {
        bestArea = area;
        best = i;
      }
    }
  }
  if (best != null) return best;
  var bestD = toleranceM;
  for (var i = 0; i < polys.length; i++) {
    final d = distanceToPolygon(polys[i], p);
    if (d <= bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// Signed shoelace area.
double polygonArea(List<Vec2> poly) {
  var a = 0.0;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    a += (poly[j].x * poly[i].y) - (poly[i].x * poly[j].y);
  }
  return a / 2;
}

/// The split view's view cone: a triangle from the camera's plan point
/// along [heading] (unit), opening [fovDeg] (horizontal), [lengthM] long.
/// Returns `[apex, left, right]` in plan metres.
List<Vec2> viewCone(Vec2 apex, Vec2 heading, double fovDeg, double lengthM) {
  final half = (fovDeg.clamp(10, 170) * math.pi / 180) / 2;
  Vec2 rot(Vec2 v, double a) => Vec2(v.x * math.cos(a) - v.y * math.sin(a), v.x * math.sin(a) + v.y * math.cos(a));
  final h = heading.length < 1e-9 ? const Vec2(0, -1) : heading * (1 / heading.length);
  return [apex, apex + rot(h, -half) * lengthM, apex + rot(h, half) * lengthM];
}

/// A perspective camera's horizontal field of view from its vertical one.
double horizontalFovDeg(double verticalFovDeg, double aspect) {
  final v = verticalFovDeg * math.pi / 180;
  return 2 * math.atan(math.tan(v / 2) * aspect) * 180 / math.pi;
}

/// Plan bounds `[minX, minZ, maxX, maxZ]` of some points, grown by
/// [marginM]; null for no points.
List<double>? boundsOf(Iterable<Vec2> points, {double marginM = 1}) {
  var minX = double.infinity, minZ = double.infinity, maxX = -double.infinity, maxZ = -double.infinity;
  var any = false;
  for (final p in points) {
    any = true;
    minX = math.min(minX, p.x);
    minZ = math.min(minZ, p.y);
    maxX = math.max(maxX, p.x);
    maxZ = math.max(maxZ, p.y);
  }
  if (!any) return null;
  return [minX - marginM, minZ - marginM, maxX + marginM, maxZ + marginM];
}
