import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ar/alignment_estimator.dart';
import 'package:technician_portal/core/ar/corner_matcher.dart';
import 'package:technician_portal/core/ar/fake_ar_engine.dart';
import 'package:technician_portal/core/ar/vec.dart';

const _matcher = CornerMatcher();
const _estimator = AlignmentEstimator();
final _yaw = degToRad(30);
final _truth = Mat4.fromYawTranslation(_yaw, const Vec3(1, 0.2, -3));

/// Column C-2's north-west corner: faces point −x and −z (out of the column).
const _column = CornerCandidate(
  id: 'col',
  posTile: Vec3(5.75, 0, 3.75),
  faceA: Vec2(-1, 0),
  faceB: Vec2(0, -1),
  angleDeg: 90,
  kind: 'column',
  structural: true,
  rank: 0.95,
  label: 'Plant Room B · column C-2',
);

/// The room corner by the door, 7.1 m from the column.
const _door = CornerCandidate(
  id: 'door',
  posTile: Vec3(0, 0, 8),
  faceA: Vec2(1, 0),
  faceB: Vec2(0, -1),
  angleDeg: 90,
  kind: 'inside',
  rank: 0.7,
  label: 'Plant Room B · corner by the door',
);

/// What a detector would report for [c] under the truth transform.
DetectedCorner _detect(
  CornerCandidate c, {
  bool swapFaces = false,
  bool flipB = false,
  Vec3 noise = Vec3.zero,
  String method = 'lidar',
}) {
  var a = rotateXz(c.faceA, _yaw);
  var b = rotateXz(c.faceB, _yaw);
  if (flipB) b = -b;
  return DetectedCorner(
    posAr: _truth.transformPoint(c.posTile) + noise,
    faceAAr: swapFaces ? b : a,
    faceBAr: swapFaces ? a : b,
    angleDeg: c.angleDeg,
    kind: c.kind == 'column' ? 'outside' : c.kind,
    method: method,
  );
}

void main() {
  group('firstCorner — one corner is a full 4-DoF placement', () {
    test('position and heading from one corner; badge amber', () {
      final obs = _matcher.firstCorner(_detect(_column), _column);
      final fit = _estimator.fit([obs]);
      expect(fit.yawDeg, closeTo(30, 1e-9));
      expect(fit.t.distanceTo(const Vec3(1, 0.2, -3)), lessThan(1e-9));
      expect(fit.quality, AlignmentQuality.placed);
      expect(fit.method, 'directions');
      expect(obs.sigmaM, ArSigma.cornerLidar);
    });

    test('faces reported in the opposite order are paired back', () {
      final obs = _matcher.firstCorner(_detect(_column, swapFaces: true), _column);
      expect(obs.faceAAr.distanceTo(rotateXz(_column.faceA, _yaw)), lessThan(1e-12));
      expect(_estimator.fit([obs]).yawDeg, closeTo(30, 1e-9));
    });

    test('the 90° ambiguity: a face normal pointing the wrong way gives a heading 90° off '
        'without the camera, and the camera side settles it', () {
      final detected = _detect(_column, flipB: true);
      final cameraAr = _truth.transformPoint(const Vec3(3, 1.5, 1.5)); // in front of the column

      final blind = _estimator.fit([_matcher.firstCorner(detected, _column)]);
      expect(blind.yawDeg, closeTo(120, 1e-6));

      final seen = _estimator.fit([_matcher.firstCorner(detected, _column, cameraAr: cameraAr)]);
      expect(seen.yawDeg, closeTo(30, 1e-9));
    });

    test('an inside corner: the camera stands inside the angle', () {
      final detected = _detect(_door, flipB: true, swapFaces: true);
      final cameraAr = _truth.transformPoint(const Vec3(3, 1.5, 5));
      final fit = _estimator.fit([_matcher.firstCorner(detected, _door, cameraAr: cameraAr)]);
      expect(fit.yawDeg, closeTo(30, 1e-9));
    });

    test('the floor finish offset raises the model point', () {
      const matcher = CornerMatcher(floorFinishOffsetM: 0.15);
      final obs = matcher.firstCorner(_detect(_column), _column);
      expect(obs.bTile.y, closeTo(0.15, 1e-12));
    });
  });

  group('matchSecond — corner B found automatically', () {
    final fitA = _estimator.fit([_matcher.firstCorner(_detect(_column), _column)]);
    const candidates = ArDemoScenario.corners;

    test('the snap is matched to the nearest same-shape candidate within 1 m', () {
      final detectedB = _detect(_door, noise: const Vec3(0.02, 0, -0.01));
      final match = _matcher.matchSecond(detectedB, fitA, candidates);
      expect(match?.id, ArDemoScenario.cornerBId);
    });

    test('a column snap never matches an inside corner', () {
      final inside = _detect(_door);
      final asColumn = DetectedCorner(
        posAr: inside.posAr,
        faceAAr: inside.faceAAr,
        faceBAr: inside.faceBAr,
        angleDeg: 90,
        kind: 'outside',
      );
      expect(_matcher.matchSecond(asColumn, fitA, candidates), isNull);
    });

    test('nothing within 1 m → no match', () {
      final far = _detect(_door, noise: const Vec3(1.5, 0, 0));
      expect(_matcher.matchSecond(far, fitA, candidates), isNull);
    });

    test('two candidates within reach are both offered, nearest first', () {
      const decoy = CornerCandidate(
        id: 'decoy',
        posTile: Vec3(0.6, 0, 8),
        faceA: Vec2(1, 0),
        faceB: Vec2(0, -1),
        angleDeg: 90,
        kind: 'inside',
      );
      final near = _matcher.candidatesNear(
        _detect(_door, noise: const Vec3(0.05, 0, 0)),
        fitA,
        [...candidates, decoy],
      );
      expect(near.map((m) => m.candidate.id), [ArDemoScenario.cornerBId, 'decoy']);
      expect(near.first.distanceM, lessThan(near.last.distanceM));
    });

    test('corner A plus corner B 7 m apart lock green', () {
      final obsA = _matcher.firstCorner(_detect(_column), _column);
      final detectedB = _detect(_door, swapFaces: true, noise: const Vec3(0.004, 0, -0.003));
      final matched = _matcher.matchSecond(detectedB, fitA, candidates)!;
      final obsB = _matcher.observe(detectedB, matched, yawPrior: fitA.yawRad);
      final fit = _estimator.fit([obsA, obsB]);
      expect(fit.quality, AlignmentQuality.locked);
      expect(fit.maxResidualM, lessThan(0.01));
      expect(fit.yawDeg, closeTo(30, 0.2));
    });
  });

  group('suggestSecond', () {
    test('at least 3 m away, structural and highly ranked first', () {
      final column = ArDemoScenario.corners.firstWhere((c) => c.id == ArDemoScenario.cornerAId);
      final suggestions = _matcher.suggestSecond(column, ArDemoScenario.corners);
      expect(suggestions.first.id, 'c-pr-b-nw');
      for (final s in suggestions) {
        expect(s.posTile.distanceXzTo(column.posTile), greaterThanOrEqualTo(CornerMatcher.lockSeparationM));
      }
      expect(suggestions.any((s) => s.id.startsWith('c-col')), isFalse);
    });

    test('falls back to the farthest when nothing is 3 m away', () {
      const near1 = CornerCandidate(
        id: 'n1',
        posTile: Vec3(1, 0, 8),
        faceA: Vec2(1, 0),
        faceB: Vec2(0, 1),
        angleDeg: 90,
        kind: 'inside',
      );
      const near2 = CornerCandidate(
        id: 'n2',
        posTile: Vec3(2, 0, 8),
        faceA: Vec2(1, 0),
        faceB: Vec2(0, 1),
        angleDeg: 90,
        kind: 'inside',
      );
      final s = _matcher.suggestSecond(_door, [near1, near2, _door]);
      expect(s.map((c) => c.id), ['n2', 'n1']);
    });
  });

  group('rankForRoom', () {
    test('only the known room\'s corners, best ranked first', () {
      final ranked = _matcher.rankForRoom(ArDemoScenario.corners, spaceName: 'Plant Room B');
      expect(ranked, hasLength(7));
      expect(ranked.first.id, ArDemoScenario.cornerAId);
      for (var i = 1; i < ranked.length; i++) {
        expect(ranked[i - 1].rank, greaterThanOrEqualTo(ranked[i].rank));
      }
    });

    test('case-insensitive; an unknown room falls back to every corner', () {
      expect(_matcher.rankForRoom(ArDemoScenario.corners, spaceName: 'riser corridor'), hasLength(2));
      expect(_matcher.rankForRoom(ArDemoScenario.corners, spaceName: 'Boiler house'), hasLength(9));
      expect(_matcher.rankForRoom(ArDemoScenario.corners), hasLength(9));
    });
  });

  group('parsing', () {
    test('CornerCandidate.fromJson tolerates string numbers and skips bad rows', () {
      final c = CornerCandidate.fromJson({
        'id': 'k1',
        'pos': ['1.5', 0, '-2'],
        'faceA': [1, 0],
        'faceB': ['0', '1'],
        'angleDeg': '90',
        'kind': 'inside',
        'structural': 'true',
        'rank': '0.7',
        'label': 'Room 1',
      })!;
      expect(c.posTile, const Vec3(1.5, 0, -2));
      expect(c.faceB, const Vec2(0, 1));
      expect(c.structural, isTrue);
      expect(c.rank, 0.7);
      expect(CornerCandidate.fromJson({'id': 'x', 'pos': [1, 2]}), isNull);
      expect(CornerCandidate.fromJson(c.toJson())!.posTile, c.posTile);
    });
  });
}
