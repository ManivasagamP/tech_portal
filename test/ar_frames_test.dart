import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ar/frames.dart';
import 'package:technician_portal/core/ar/vec.dart';

void expectVec(Vec3 actual, Vec3 expected, {double eps = 1e-9}) {
  expect(actual.x, closeTo(expected.x, eps), reason: 'x of $actual');
  expect(actual.y, closeTo(expected.y, eps), reason: 'y of $actual');
  expect(actual.z, closeTo(expected.z, eps), reason: 'z of $actual');
}

void main() {
  // CONTRACT C2 golden vectors — asserted by the server's frames.ts tests too.
  final frameA = Mat4([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1000, 2000, 0, 1]);
  final frameB = Mat4([0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 1000, 2000, 0, 1]);

  group('Golden A (translation only)', () {
    test('world (1012.5, 2008, 1.5) → tile (12.5, 1.5, −8)', () {
      expectVec(projectToTile(const Vec3(1012.5, 2008.0, 1.5), frameA), const Vec3(12.5, 1.5, -8.0));
    });

    test('and back', () {
      expectVec(tileToProject(const Vec3(12.5, 1.5, -8.0), frameA), const Vec3(1012.5, 2008.0, 1.5));
    });

    test('normal world (−1, 0, 0) → tile (−1, 0, 0); up (0, 0, 1) → (0, 1, 0)', () {
      expectVec(dirProjectToTile(const Vec3(-1, 0, 0), frameA), const Vec3(-1, 0, 0));
      expectVec(dirProjectToTile(const Vec3(0, 0, 1), frameA), const Vec3(0, 1, 0));
    });

    test('directions ignore the translation', () {
      expectVec(dirTileToProject(const Vec3(0, 1, 0), frameA), const Vec3(0, 0, 1));
    });
  });

  group('Golden B (90° about Z, then translation)', () {
    test('world (1000, 2001, 3) → tile (1, 3, 0)', () {
      expectVec(projectToTile(const Vec3(1000, 2001, 3), frameB), const Vec3(1, 3, 0));
    });

    test('and back', () {
      expectVec(tileToProject(const Vec3(1, 3, 0), frameB), const Vec3(1000, 2001, 3));
    });

    test('a direction rotates with the frame', () {
      // World +Y is local +X under this frame, so tile +X.
      expectVec(dirProjectToTile(const Vec3(0, 1, 0), frameB), const Vec3(1, 0, 0));
      expectVec(dirTileToProject(const Vec3(1, 0, 0), frameB), const Vec3(0, 1, 0));
    });
  });

  group('axis swap', () {
    test('Z-up → Y-up is (x, z, −y), and the inverse undoes it', () {
      expectVec(zUpToYUp(const Vec3(1, 2, 3)), const Vec3(1, 3, -2));
      expectVec(yUpToZUp(zUpToYUp(const Vec3(1, 2, 3))), const Vec3(1, 2, 3));
    });

    test('round trips through a rotated frame', () {
      final frame = Mat4.fromYawTranslation(0.7, const Vec3(5, 6, 7)).multiply(frameB);
      const p = Vec3(123.4, -56.7, 8.9);
      expectVec(tileToProject(projectToTile(p, frame), frame), p, eps: 1e-9);
    });
  });

  group('Mat4', () {
    test('column-major: translation at 12, 13, 14', () {
      expectVec(frameA.translation, const Vec3(1000, 2000, 0));
      expect(frameA.at(0, 3), 1000);
    });

    test('fromYawTranslation follows the contract rotation', () {
      const yaw = math.pi / 6;
      final m = Mat4.fromYawTranslation(yaw, Vec3.zero);
      // x' = x cos + z sin; z' = −x sin + z cos
      expectVec(m.transformPoint(const Vec3(1, 0, 0)), Vec3(math.cos(yaw), 0, -math.sin(yaw)));
      expectVec(m.transformPoint(const Vec3(0, 0, 1)), Vec3(math.sin(yaw), 0, math.cos(yaw)));
    });

    test('invertRigid undoes a rigid transform', () {
      final m = Mat4.fromYawTranslation(1.1, const Vec3(3, -2, 9)).multiply(frameB);
      expect(m.multiply(m.invertRigid()).closeTo(Mat4.identity(), eps: 1e-9), isTrue);
      expect(m.invertRigid().multiply(m).closeTo(Mat4.identity(), eps: 1e-9), isTrue);
    });

    test('multiply applies the right-hand matrix first', () {
      final translate = Mat4.fromYawTranslation(0, const Vec3(10, 0, 0));
      final rotate = Mat4.fromYawTranslation(math.pi / 2, Vec3.zero);
      // rotate then translate: (1,0,0) → (0,0,−1) → (10,0,−1)
      expectVec(translate.multiply(rotate).transformPoint(const Vec3(1, 0, 0)), const Vec3(10, 0, -1));
    });

    test('tryParse accepts 16 numbers (strings too) and rejects anything else', () {
      expect(Mat4.tryParse(['1', 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]), isNotNull);
      expect(Mat4.tryParse([1, 2, 3]), isNull);
      expect(Mat4.tryParse(null), isNull);
      expect(Mat4.tryParse(List.filled(16, 'x')), isNull);
    });
  });

  group('headingOf / rotateXz', () {
    test('rotating a direction by θ adds θ to its heading', () {
      const v = Vec2(0.3, -0.8);
      const theta = 0.9;
      expect(wrapAngle(headingOf(rotateXz(v, theta)) - headingOf(v)), closeTo(theta, 1e-12));
    });
  });
}
