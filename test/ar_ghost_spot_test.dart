import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ar/corner_matcher.dart';
import 'package:technician_portal/core/ar/fake_ar_engine.dart';
import 'package:technician_portal/core/ar/ghost_spot.dart';
import 'package:technician_portal/core/ar/vec.dart';
import 'package:technician_portal/domain/ar_models.dart';

const _finder = GhostSpotFinder();

List<CornerCandidate> get _plantRoomCorners => [
      for (final c in ArDemoScenario.corners)
        if (c.label.startsWith('Plant Room B')) c,
    ];

void main() {
  group('leave a board: where the ghost board goes', () {
    final plan = ArDemoScenario.plan();

    test('a flat wall near the room entrance, centre 1.5 m up, facing the room', () {
      final spot = _finder.best(
        corners: _plantRoomCorners,
        markers: ArDemoScenario.markers,
        cameraTile: const Vec3(3, 1.5, 5),
        plan: plan,
      )!;
      expect(spot.cornerId, ArDemoScenario.cornerBId, reason: 'the corner by the door');
      expect(spot.posTile.distanceTo(const Vec3(0, 1.5, 6.8)), lessThan(1e-9));
      expect(spot.normalTile, const Vec3(1, 0, 0));
      expect(spot.coverageAfter, greaterThan(spot.coverageBefore));
    });

    test('never in a door swing, on equipment or off a wall', () {
      final spots = _finder.suggest(
        corners: _plantRoomCorners,
        markers: ArDemoScenario.markers,
        cameraTile: const Vec3(3, 1.5, 5),
        plan: plan,
        limit: 20,
      );
      expect(spots, isNotEmpty);
      for (final s in spots) {
        final p = s.posTile;
        final onRoomWall = p.x.abs() < 1e-9 || (p.x - 12).abs() < 1e-9 || p.z.abs() < 1e-9 || (p.z - 8).abs() < 1e-9;
        expect(onRoomWall, isTrue, reason: '$p');
        // The door opening is x 2–3 on the z = 8 wall.
        final nearDoor = (p.z - 8).abs() < 1e-9 && p.x > 1.1 && p.x < 3.9;
        expect(nearDoor, isFalse, reason: '$p is in the door swing');
        expect(p.y, closeTo(1.5, 1e-12));
      }
    });

    test('spots are at least 2 m apart, and 2 m from existing boards', () {
      final markers = [
        const ManifestMarker(
          code: '7K3QX9R',
          label: 'L03-M07',
          status: 'active',
          accuracyClass: 'feature',
          mounting: 'wall',
          posTile: Vec3(0, 1.5, 6.5),
          normalTile: Vec3(1, 0, 0),
          sigmaM: 0.02,
        ),
      ];
      final spots = _finder.suggest(
        corners: _plantRoomCorners,
        markers: markers,
        cameraTile: const Vec3(3, 1.5, 5),
        plan: plan,
        limit: 5,
      );
      for (final s in spots) {
        expect(s.posTile.distanceXzTo(markers.first.posTile), greaterThanOrEqualTo(2));
      }
      for (var i = 0; i < spots.length; i++) {
        for (var j = i + 1; j < spots.length; j++) {
          expect(spots[i].posTile.distanceXzTo(spots[j].posTile), greaterThanOrEqualTo(2));
        }
      }
    });

    test('the floor finish offset raises the board with the floor', () {
      final spot = _finder.best(
        corners: _plantRoomCorners,
        cameraTile: const Vec3(3, 1.5, 5),
        floorFinishOffsetM: 0.2,
      )!;
      expect(spot.posTile.y, closeTo(1.7, 1e-12));
    });

    test('works without a plan (corners only), and with no corners returns nothing', () {
      expect(_finder.best(corners: _plantRoomCorners, cameraTile: const Vec3(3, 1.5, 5)), isNotNull);
      expect(_finder.best(corners: const []), isNull);
    });

    test('a second board goes on a facing or adjacent wall 3–10 m away', () {
      final first = _finder.best(
        corners: _plantRoomCorners,
        markers: ArDemoScenario.markers,
        cameraTile: const Vec3(3, 1.5, 5),
        plan: plan,
      )!;
      final pair = _finder.pairFor(
        first,
        corners: _plantRoomCorners,
        markers: ArDemoScenario.markers,
        plan: plan,
      )!;
      final d = pair.posTile.distanceXzTo(first.posTile);
      expect(d, inInclusiveRange(3, 10));
      expect(pair.normalTile.dot(first.normalTile), lessThanOrEqualTo(0.5), reason: 'not the same wall');
    });
  });
}
