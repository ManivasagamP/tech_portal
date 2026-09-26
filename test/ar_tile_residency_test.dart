import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ar/tile_residency.dart';
import 'package:technician_portal/core/ar/vec.dart';
import 'package:technician_portal/domain/ar_models.dart';

/// A row of 8 m cells along x: tile i covers x ∈ [8i, 8i + 8], z ∈ [0, 8].
List<ManifestTile> _row(int count, {int triangles = 50000}) => [
      for (var i = 0; i < count; i++)
        ManifestTile(
          hash: 't$i',
          url: '/api/bim/ar/tiles/t$i',
          bytes: 1000,
          layer: ArLayer.mep,
          bboxMin: Vec3(8.0 * i, 0, 0),
          bboxMax: Vec3(8.0 * i + 8, 3, 8),
          triangleCount: triangles,
          buildId: 'b',
        ),
    ];

Vec3 _at(double x) => Vec3(x, 1.5, 4);

void main() {
  const residency = TileResidency();

  test('loads tiles within 15 m, nearest first', () {
    final plan = residency.plan(cameraTile: _at(4), tiles: _row(6), loaded: {});
    expect(plan.load.map((t) => t.hash), ['t0', 't1', 't2']);
    expect(plan.unload, isEmpty);
  });

  test('a scripted walk along a cell boundary never thrashes', () {
    final tiles = _row(6);
    final loaded = <String>{};
    var loads = 0;
    var unloads = 0;

    void walkTo(double x) {
      final plan = residency.plan(cameraTile: _at(x), tiles: tiles, loaded: loaded);
      loads += plan.load.length;
      unloads += plan.unload.length;
      loaded
        ..addAll(plan.load.map((t) => t.hash))
        ..removeAll(plan.unload);
    }

    walkTo(1.5); // t2 (x 16–24) is 14.5 m away: loads
    expect(loaded, {'t0', 't1', 't2'});
    final loadsAfterStart = loads;

    // Pace back and forth across the 15 m line for t2.
    for (var i = 0; i < 20; i++) {
      walkTo(i.isEven ? 0.5 : 1.5); // 15.5 m ↔ 14.5 m
    }
    expect(loads, loadsAfterStart, reason: 'no reloads while pacing');
    expect(unloads, 0, reason: 'kept within radius + hysteresis (18 m)');

    walkTo(-2.5); // 18.5 m: past the hysteresis band
    expect(loaded.contains('t2'), isFalse);

    walkTo(0.5); // 15.5 m, not loaded: stays out until within 15 m
    expect(loaded.contains('t2'), isFalse);
    walkTo(1.5);
    expect(loaded.contains('t2'), isTrue);
  });

  test('never exceeds the triangle budget', () {
    final plan = residency.plan(
      cameraTile: _at(4),
      tiles: _row(6),
      loaded: {},
      triangleBudget: 120000,
    );
    expect(plan.load.map((t) => t.hash), ['t0', 't1']);
    final triangles = plan.load.fold<int>(0, (s, t) => s + t.triangleCount);
    expect(triangles, lessThanOrEqualTo(120000));
  });

  test('the target\'s tiles are always resident, even far away or over budget', () {
    final plan = residency.plan(
      cameraTile: _at(4),
      tiles: _row(6),
      loaded: {},
      pinned: {'t5'},
      triangleBudget: 120000,
    );
    expect(plan.load.map((t) => t.hash), ['t5', 't0']);
  });

  test('a loaded tile keeps its place when the budget is contended', () {
    // Camera between t0 and t1; t1 loaded, t0 not; budget for one tile only.
    final plan = residency.plan(
      cameraTile: _at(8.5),
      tiles: _row(2),
      loaded: {'t1'},
      triangleBudget: 60000,
    );
    // t0 is 0.5 m away, t1 0 m: t1 stays, and t0 cannot also fit.
    expect(plan.load, isEmpty);
    expect(plan.unload, isEmpty);
  });

  test('tiles no longer in the manifest are unloaded', () {
    final plan = residency.plan(cameraTile: _at(4), tiles: _row(1), loaded: {'t0', 'gone'});
    expect(plan.unload, ['gone']);
  });

  test('distance is to the box, not its centre', () {
    final tile = _row(1).single;
    expect(tile.distanceTo(const Vec3(4, 1, 4)), 0);
    expect(tile.distanceTo(const Vec3(11, 1, 4)), closeTo(3, 1e-12));
    expect(tile.distanceTo(const Vec3(11, 7, 12)), closeTo(const Vec3(3, 4, 4).length, 1e-12));
  });
}
