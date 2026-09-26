import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ar/vec.dart';
import 'package:technician_portal/core/bim_viewer/plan_view_math.dart';

/// The 2D plan's viewport and hit tests (docs/bim-viewer.md §5).
void main() {
  void close(Vec2 a, Vec2 b, [double eps = 1e-9]) {
    expect((a.x - b.x).abs() < eps && (a.y - b.y).abs() < eps, isTrue, reason: '$a ≉ $b');
  }

  group('PlanViewport', () {
    test('fit centres the plan and uses the tighter axis', () {
      final vp = PlanViewport.fit([0, 0, 20, 10], 400, 400, padding: 0);
      expect(vp.scale, 20); // 400 px / 20 m
      close(vp.toScreen(const Vec2(10, 5)), const Vec2(200, 200));
    });

    test('toPlan inverts toScreen', () {
      const vp = PlanViewport(scale: 13.5, offset: Vec2(-40, 22));
      for (final p in const [Vec2(0, 0), Vec2(3.2, -7.1), Vec2(100, 50)]) {
        close(vp.toPlan(vp.toScreen(p)), p, 1e-9);
      }
    });

    test('zoomAbout keeps the plan point under the fingers fixed', () {
      final vp = PlanViewport.fit([0, 0, 30, 18], 360, 640);
      const focal = Vec2(123, 456);
      final before = vp.toPlan(focal);
      final z = vp.zoomAbout(focal, 2.5);
      expect(z.scale, closeTo(vp.scale * 2.5, 1e-9));
      close(z.toPlan(focal), before, 1e-9);
    });

    test('zoom is clamped; pan moves the offset', () {
      const vp = PlanViewport(scale: 300, offset: Vec2(0, 0));
      expect(vp.zoomAbout(const Vec2(0, 0), 10).scale, PlanViewport.maxScale);
      expect(vp.zoomAbout(const Vec2(0, 0), 1e-6).scale, PlanViewport.minScale);
      close(vp.panBy(const Vec2(5, -3)).offset, const Vec2(5, -3));
    });

    test('centreOn and shows (walk-follow)', () {
      const vp = PlanViewport(scale: 10, offset: Vec2(0, 0));
      expect(vp.shows(const Vec2(50, 50), 200, 200), isFalse);
      final c = vp.centreOn(const Vec2(50, 50), 200, 200);
      close(c.toScreen(const Vec2(50, 50)), const Vec2(100, 100));
      expect(c.shows(const Vec2(50, 50), 200, 200), isTrue);
    });
  });

  group('hit tests', () {
    const room = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)];
    const pump = [Vec2(4, 4), Vec2(6, 4), Vec2(6, 6), Vec2(4, 6)];

    test('pointInPolygon and distanceToPolygon', () {
      expect(pointInPolygon(pump, const Vec2(5, 5)), isTrue);
      expect(pointInPolygon(pump, const Vec2(7, 5)), isFalse);
      expect(distanceToPolygon(pump, const Vec2(5, 5)), 0);
      expect(distanceToPolygon(pump, const Vec2(7, 5)), closeTo(1, 1e-12));
      expect(distanceToSegment(const Vec2(0, 1), const Vec2(-1, 0), const Vec2(1, 0)), closeTo(1, 1e-12));
    });

    test('the smallest containing polygon wins (a pump inside its plant room)', () {
      expect(hitPolygon(const [room, pump], const Vec2(5, 5), 0.5), 1);
      expect(hitPolygon(const [room, pump], const Vec2(1, 1), 0.5), 0);
    });

    test('outside everything: nearest within tolerance, else null', () {
      expect(hitPolygon(const [pump], const Vec2(6.3, 5), 0.5), 0);
      expect(hitPolygon(const [pump], const Vec2(8, 5), 0.5), isNull);
      expect(hitPolygon(const [], const Vec2(0, 0), 5), isNull);
    });

    test('polygonArea is signed shoelace', () {
      expect(polygonArea(pump).abs(), closeTo(4, 1e-12));
    });
  });

  group('view cone', () {
    test('symmetric about the heading, apex first', () {
      final cone = viewCone(const Vec2(0, 0), const Vec2(0, -1), 90, 4);
      close(cone[0], const Vec2(0, 0));
      expect(cone[1].distanceTo(cone[0]), closeTo(4, 1e-9));
      expect(cone[2].distanceTo(cone[0]), closeTo(4, 1e-9));
      // 90° cone looking −Z: the edges are at ±45° off −Z.
      expect(cone[1].y, closeTo(-4 * math.cos(math.pi / 4), 1e-9));
      expect(cone[1].x, closeTo(-cone[2].x, 1e-9));
    });

    test('a zero heading still draws (looks −Z)', () {
      final cone = viewCone(const Vec2(1, 1), const Vec2(0, 0), 60, 2);
      expect(cone[1].y, lessThan(1));
    });

    test('horizontal FOV widens with aspect', () {
      expect(horizontalFovDeg(60, 1), closeTo(60, 1e-9));
      expect(horizontalFovDeg(60, 2), greaterThan(60));
      expect(horizontalFovDeg(60, 0.5), lessThan(60));
    });
  });

  test('boundsOf grows by the margin; null for nothing', () {
    expect(boundsOf(const [Vec2(1, 2), Vec2(5, -3)], marginM: 1), [0, -4, 6, 3]);
    expect(boundsOf(const []), isNull);
  });
}
