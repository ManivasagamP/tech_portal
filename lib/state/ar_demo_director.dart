import 'dart:math' as math;

import '../core/ar/alignment_estimator.dart';
import '../core/ar/corner_matcher.dart';
import '../core/ar/marker_code.dart';
import '../core/ar/vec.dart';
import 'ar_session_controller.dart' show ArMarkerSighting;
import 'ar_view_models.dart';

/// Demo mode's stand-in for the physical world.
///
/// The sample building lives in the tile frame; the "phone" lives in an AR
/// frame that is the tile frame turned by a hidden yaw and shifted by a
/// hidden offset, exactly as on site. Every sighting the director hands out
/// is a model point pushed through that hidden pose plus a few millimetres
/// of noise, so the real estimator, the real corner matcher and the real
/// honesty rules (amber, green, red) run on it unchanged. Nothing here is
/// shown to the user as a measurement of a real building: the Demo banner
/// stays up the whole time.
class ArDemoDirector {
  ArDemoDirector({required this.floor, int seed = 7})
    : _random = math.Random(seed),
      trueArFromTile = Mat4.fromYawTranslation(_yaw, const Vec3(2.3, 0, -1.7));

  static const _yaw = 0.41;

  final ArFloorContext floor;
  final math.Random _random;

  /// The pose the fit should rediscover.
  final Mat4 trueArFromTile;

  static const demoHost = 'FE.DEMO';

  double _noise(double sigmaM) => (_random.nextDouble() * 2 - 1) * sigmaM;

  Vec3 _toAr(Vec3 tile, {double sigmaM = 0.006}) {
    final p = trueArFromTile.transformPoint(tile);
    return Vec3(p.x + _noise(sigmaM), p.y + _noise(sigmaM * 0.3), p.z + _noise(sigmaM));
  }

  /// A LiDAR-grade snap of [c]. The faces come back in swapped order half
  /// the time, so the matcher's pairing logic is exercised, not bypassed.
  DetectedCorner cornerFor(CornerCandidate c) {
    final pos = _toAr(Vec3(c.posTile.x, c.posTile.y + floor.floorFinishOffsetM, c.posTile.z));
    final a = rotateXz(c.faceA, _yaw + _noise(0.004));
    final b = rotateXz(c.faceB, _yaw + _noise(0.004));
    final swap = _random.nextBool();
    return DetectedCorner(
      posAr: pos,
      faceAAr: swap ? b : a,
      faceBAr: swap ? a : b,
      angleDeg: c.angleDeg + _noise(1.2),
      kind: c.kind,
      method: 'lidar',
    );
  }

  /// A steady, square-on sighting of board [m] from about a metre.
  ArMarkerSighting markerFor(ArMarkerInfo m) => sightingAt(m.code, m.posTile, m.normalTile);

  /// A sighting of a board with [code] stuck at [posTile] facing [normalTile]
  /// (used for the spare board the user "sticks" on the ghost outline).
  ArMarkerSighting sightingAt(String code, Vec3 posTile, Vec3 normalTile, {double scalePct = 100.2}) {
    final n = trueArFromTile.transformDir(normalTile);
    return ArMarkerSighting(
      seq: 0,
      code: code,
      raw: MarkerCode.qrPayload(code, webHost: demoHost),
      anchorId: 'demo-anchor-$code',
      centreAr: _toAr(posTile, sigmaM: 0.004),
      normalAr: n,
      method: 'plane',
      spreadMm: 3 + _random.nextDouble() * 4,
      distanceM: 1.05 + _random.nextDouble() * 0.2,
      viewAngleDeg: 4 + _random.nextDouble() * 8,
      qrEdgeMm: 115 * scalePct / 100,
    );
  }

  /// Where a person stands to make [o]: 1.2 m in front of a board, facing
  /// it, or 2.5 m out from a corner along its bisector (AR world, eye
  /// height 1.5 m above the corner's floor).
  (Vec3, Vec3) cameraFor(ArObservation o) {
    Vec3 out;
    double back;
    if (o is MarkerObs) {
      out = Vec3(o.normalAr.x, 0, o.normalAr.z).normalized;
      back = 1.2;
    } else if (o is CornerObs) {
      final b = o.faceAAr + o.faceBAr;
      out = Vec3(b.x, 0, b.y).normalized;
      back = 2.5;
    } else {
      out = const Vec3(0, 0, 1);
      back = 2;
    }
    final eye = o is MarkerObs ? o.aAr.y : o.aAr.y + 1.5;
    final pos = Vec3(o.aAr.x + out.x * back, eye, o.aAr.z + out.z * back);
    return (pos, -out);
  }

  /// A board sighting that is deliberately a bad read (too far, at an
  /// angle) so the coaching chips can be seen once.
  ArMarkerSighting awkwardSightingFor(ArMarkerInfo m) {
    final s = markerFor(m);
    return ArMarkerSighting(
      seq: 0,
      code: s.code,
      raw: s.raw,
      anchorId: s.anchorId,
      centreAr: s.centreAr,
      normalAr: s.normalAr,
      method: s.method,
      spreadMm: 22,
      distanceM: 2.6,
      viewAngleDeg: 41,
      qrEdgeMm: s.qrEdgeMm,
    );
  }
}
