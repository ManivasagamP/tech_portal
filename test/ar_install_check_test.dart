import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ar/install_check.dart';
import 'package:technician_portal/core/ar/vec.dart';

const _check = InstallCheck();
const _planned = Vec3(4, 1.5, 2);

InstallCheckInput _input({
  String scanned = '7K3QX9R',
  String? scannedLabel,
  double? qrEdgeMm = 115.2,
  bool manualScaleConfirmed = false,
  bool locked = true,
  Vec3? measuredTile = const Vec3(4.011, 1.5, 2),
  Vec3? measuredAr,
  InstallPairRef? pair,
  double? tiltDeg = 0.8,
  Vec3? boardUpAr,
  Vec3? boardNormalAr,
  String mounting = 'wall',
}) =>
    InstallCheckInput(
      expectedCode: '7K3QX9-R',
      scannedCode: scanned,
      scannedLabel: scannedLabel,
      plannedPosTile: _planned,
      qrEdgeMm: qrEdgeMm,
      manualScaleConfirmed: manualScaleConfirmed,
      sessionLocked: locked,
      measuredPosTile: measuredTile,
      measuredPosAr: measuredAr,
      pair: pair,
      tiltDeg: tiltDeg,
      boardUpAr: boardUpAr,
      boardNormalAr: boardNormalAr,
      mounting: mounting,
    );

void main() {
  group('1. right board?', () {
    test('a swap names the board that was actually scanned', () {
      final r = _check.run(_input(scanned: '4Q2MA76', scannedLabel: 'L03-M10'));
      expect(r.rightBoard, isFalse);
      expect(r.swappedWithLabel, 'L03-M10');
      expect(r.messageKeys, [InstallCheckMessage.swap]);
      expect(r.positionVerdict, InstallVerdict.unchecked);
      expect(r.allGood, isFalse);
    });

    test('an unknown swap falls back to the scanned code', () {
      final r = _check.run(_input(scanned: '4Q2MA76'));
      expect(r.swappedWithLabel, '4Q2MA7-6');
    });

    test('codes compare in any form (display, case)', () {
      expect(_check.run(_input(scanned: '7k3qx9-r')).rightBoard, isTrue);
    });
  });

  group('2. print scale', () {
    test('printed at 94% → reprint, nothing else checked', () {
      final r = _check.run(_input(qrEdgeMm: 108.1));
      expect(r.scaleOk, isFalse);
      expect(r.scalePct, closeTo(94.0, 0.01));
      expect(r.messageKeys, [InstallCheckMessage.codeOk, InstallCheckMessage.scaleOff]);
      expect(r.positionVerdict, InstallVerdict.unchecked);
    });

    test('within ±2% passes', () {
      final r = _check.run(_input(qrEdgeMm: 117.0));
      expect(r.scaleOk, isTrue);
      expect(r.messageKeys, contains(InstallCheckMessage.scaleOk));
    });

    test('no depth sensor: ask to confirm the 100 mm line first', () {
      final r = _check.run(_input(qrEdgeMm: null));
      expect(r.scaleNeedsConfirm, isTrue);
      expect(r.scaleOk, isFalse);
      expect(r.messageKeys.last, InstallCheckMessage.scaleConfirm);
    });

    test('no depth sensor, confirmed: carries on', () {
      final r = _check.run(_input(qrEdgeMm: null, manualScaleConfirmed: true));
      expect(r.scaleOk, isTrue);
      expect(r.scalePct, isNull);
      expect(r.messageKeys, contains(InstallCheckMessage.scaleConfirmed));
    });
  });

  group('3. position (session locked on 2+ boards)', () {
    test('≤ 3 cm → Active, then level', () {
      final r = _check.run(_input());
      expect(r.positionM, closeTo(0.011, 1e-9));
      expect(r.positionVerdict, InstallVerdict.ok);
      expect(r.expectActive, isTrue);
      expect(r.messageKeys, [
        InstallCheckMessage.codeOk,
        InstallCheckMessage.scaleOk,
        InstallCheckMessage.positionOk,
        InstallCheckMessage.level,
      ]);
      expect(r.allGood, isTrue);
    });

    test('3–10 cm → keep as built (Derived) or move it', () {
      final r = _check.run(_input(measuredTile: const Vec3(4.06, 1.5, 2)));
      expect(r.positionVerdict, InstallVerdict.keepAsBuilt);
      expect(r.expectActive, isFalse);
      expect(r.allGood, isFalse);
      expect(r.messageKeys, contains(InstallCheckMessage.keepAsBuilt));
    });

    test('> 10 cm → wrong spot, and tilt is not checked until it moves', () {
      final r = _check.run(_input(measuredTile: const Vec3(4.25, 1.5, 2)));
      expect(r.positionVerdict, InstallVerdict.wrongSpot);
      expect(r.tiltDeg, isNull);
      expect(r.messageKeys.last, InstallCheckMessage.wrongSpot);
    });
  });

  group('3. position (first boards on a floor)', () {
    const pairPlanned = Vec3(4, 1.5, 7); // 5 m from this board's plan
    const pairAr = Vec3(10, 0, -3);

    test('no other board up yet → installed, checked when the next goes up', () {
      final r = _check.run(_input(locked: false, measuredTile: null));
      expect(r.firstOnFloor, isTrue);
      expect(r.positionVerdict, InstallVerdict.unchecked);
      expect(r.messageKeys, contains(InstallCheckMessage.firstOnFloor));
      expect(r.expectActive, isFalse);
      expect(r.allGood, isTrue);
    });

    test('pair distance within 2 cm of plan → both Active', () {
      final r = _check.run(_input(
        locked: false,
        measuredTile: null,
        measuredAr: pairAr + const Vec3(0, 0, 5.012),
        pair: const InstallPairRef(label: 'L03-M08', plannedPosTile: pairPlanned, observedAr: pairAr),
      ));
      expect(r.positionVerdict, InstallVerdict.ok);
      expect(r.pairLabel, 'L03-M08');
      expect(r.positionM, closeTo(0.012, 1e-9));
      expect(r.messageKeys, contains(InstallCheckMessage.bothActive));
      expect(r.expectActive, isTrue);
    });

    test('pair distance off by 5 cm → wrong spot', () {
      final r = _check.run(_input(
        locked: false,
        measuredTile: null,
        measuredAr: pairAr + const Vec3(0, 0, 5.05),
        pair: const InstallPairRef(label: 'L03-M08', plannedPosTile: pairPlanned, observedAr: pairAr),
      ));
      expect(r.positionVerdict, InstallVerdict.wrongSpot);
    });
  });

  group('4. tilt', () {
    test('over 3° → straighten it', () {
      final r = _check.run(_input(tiltDeg: 4.2));
      expect(r.tiltOk, isFalse);
      expect(r.expectActive, isFalse);
      expect(r.messageKeys.last, InstallCheckMessage.straighten);
      expect(r.allGood, isFalse);
    });

    test('measured from the board\'s up vector when not reported', () {
      const a = 5 * math.pi / 180;
      final r = _check.run(_input(tiltDeg: null, boardUpAr: Vec3(math.sin(a), math.cos(a), 0)));
      expect(r.tiltDeg, closeTo(5, 1e-9));
      expect(r.tiltOk, isFalse);
    });

    test('a leaning board counts too (normal off horizontal)', () {
      const a = 2 * math.pi / 180;
      final r = _check.run(_input(
        tiltDeg: null,
        boardUpAr: const Vec3(0, 1, 0),
        boardNormalAr: Vec3(math.cos(a), math.sin(a), 0),
      ));
      expect(r.tiltDeg, closeTo(2, 1e-9));
      expect(r.tiltOk, isTrue);
    });

    test('unmeasurable tilt is not held against the installer', () {
      final r = _check.run(_input(tiltDeg: null));
      expect(r.tiltDeg, isNull);
      expect(r.tiltOk, isTrue);
    });

    test('a floor board has no level to check', () {
      final r = _check.run(_input(tiltDeg: 12, mounting: 'floor'));
      expect(r.tiltDeg, isNull);
      expect(r.tiltOk, isTrue);
    });
  });

  test('checks JSON for confirm-install', () {
    final r = _check.run(_input());
    expect(r.toChecksJson(), {
      'code': true,
      'scalePct': 100.2,
      'positionM': 0.011,
      'tiltDeg': 0.8,
    });
  });
}
