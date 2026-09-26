import 'dart:math' as math;

import 'marker_code.dart';
import 'vec.dart';

/// Another board already up on this floor and seen in the same session —
/// the reference for the pair-distance check when the session isn't locked
/// yet (the first boards on a floor).
class InstallPairRef {
  const InstallPairRef({
    required this.label,
    required this.plannedPosTile,
    required this.observedAr,
  });

  final String label;
  final Vec3 plannedPosTile;

  /// Where that board's centre was observed in this session's AR world.
  final Vec3 observedAr;
}

/// Everything the phone measured when the installer scanned a board. The
/// installer never measures anything; each field comes from the scan, the
/// depth sensor or the current fit.
class InstallCheckInput {
  const InstallCheckInput({
    required this.expectedCode,
    required this.scannedCode,
    required this.plannedPosTile,
    this.scannedLabel,
    this.printedQrMm = 115,
    this.qrEdgeMm,
    this.manualScaleConfirmed = false,
    this.sessionLocked = false,
    this.measuredPosTile,
    this.measuredPosAr,
    this.pair,
    this.tiltDeg,
    this.boardUpAr,
    this.boardNormalAr,
    this.mounting = 'wall',
  });

  /// The board this stop expects (canonical or display form).
  final String expectedCode;

  /// What was actually scanned (canonical or display form).
  final String scannedCode;

  /// When the scanned board is another planned board, its label — "This is
  /// L03-M10's board" names it so the swap can be fixed.
  final String? scannedLabel;

  /// The board's planned centre, tile frame.
  final Vec3 plannedPosTile;

  /// The QR edge printed on the board (115 mm on A4, 170 mm on A3).
  final int printedQrMm;

  /// The QR edge measured from depth or LiDAR; null without a depth sensor.
  final double? qrEdgeMm;

  /// Without depth, the installer taps to confirm the printed 100 mm line
  /// really measures 100 mm.
  final bool manualScaleConfirmed;

  /// The session is locked (green) on two or more active boards or
  /// structural corners, so the board's position can be checked against
  /// the plan directly.
  final bool sessionLocked;

  /// The board's measured centre in the tile frame (from the locked fit).
  final Vec3? measuredPosTile;

  /// The board's measured centre in the AR world (for the pair check).
  final Vec3? measuredPosAr;

  /// Another board already installed on this floor, seen this session.
  final InstallPairRef? pair;

  /// Measured tilt, when the engine reports it directly.
  final double? tiltDeg;

  /// The board's "up" (the QR's top edge direction) in the AR world.
  final Vec3? boardUpAr;

  /// The board's facing normal in the AR world.
  final Vec3? boardNormalAr;

  /// `wall | column | floor`; a floor board has no level to check.
  final String mounting;
}

abstract final class InstallVerdict {
  static const ok = 'ok';
  static const keepAsBuilt = 'keepAsBuilt';
  static const wrongSpot = 'wrongSpot';
  static const unchecked = 'unchecked';
}

/// i18n keys for each line of the self-check (all under `ar.installCheck.*`,
/// in both en.json and ar.json). The screen shows them in order as the
/// checklist ("Right board, right spot · Printed at 100% · 1.1 cm from the
/// plan · Flat and level").
abstract final class InstallCheckMessage {
  static const codeOk = 'ar.installCheck.codeOk';
  static const swap = 'ar.installCheck.swap';
  static const scaleOk = 'ar.installCheck.scaleOk';
  static const scaleOff = 'ar.installCheck.scaleOff';
  static const scaleConfirm = 'ar.installCheck.scaleConfirm';
  static const scaleConfirmed = 'ar.installCheck.scaleConfirmed';
  static const positionOk = 'ar.installCheck.positionOk';
  static const bothActive = 'ar.installCheck.bothActive';
  static const keepAsBuilt = 'ar.installCheck.keepAsBuilt';
  static const wrongSpot = 'ar.installCheck.wrongSpot';
  static const firstOnFloor = 'ar.installCheck.firstOnFloor';
  static const level = 'ar.installCheck.level';
  static const straighten = 'ar.installCheck.straighten';
}

class InstallCheckResult {
  const InstallCheckResult({
    required this.rightBoard,
    required this.scaleOk,
    required this.positionVerdict,
    required this.tiltOk,
    required this.firstOnFloor,
    required this.messageKeys,
    this.swappedWithLabel,
    this.scalePct,
    this.positionM,
    this.tiltDeg,
    this.scaleNeedsConfirm = false,
    this.pairLabel,
    this.expectActive = false,
  });

  final bool rightBoard;

  /// Set on a swap: the label of the board actually scanned.
  final String? swappedWithLabel;

  /// Measured print scale in percent (100 = exact); null when not measured.
  final double? scalePct;
  final bool scaleOk;

  /// No depth sensor and the 100 mm line isn't confirmed yet: ask, then run
  /// the check again with `manualScaleConfirmed: true`.
  final bool scaleNeedsConfirm;

  /// Metres from the plan (locked session), or the pair-distance error
  /// (first boards on a floor).
  final double? positionM;

  /// [InstallVerdict] values.
  final String positionVerdict;

  /// Set when the position came from the pair check against this board.
  final String? pairLabel;

  final double? tiltDeg;

  /// True when the tilt is within 3°, or wasn't measurable.
  final bool tiltOk;

  /// Nothing to check the position against yet: "Installed. Checked when
  /// the next board goes up".
  final bool firstOnFloor;

  /// [InstallCheckMessage] keys, in checklist order.
  final List<String> messageKeys;

  /// Whether the server should make this board Active on confirm (the
  /// position was checked and is within 3 cm, or the pair distance within
  /// 2 cm). Otherwise it confirms as Installed.
  final bool expectActive;

  /// Everything passed or was legitimately unchecked (first on the floor):
  /// the "Next board" button, with an automatic photo.
  bool get allGood =>
      rightBoard &&
      scaleOk &&
      tiltOk &&
      (positionVerdict == InstallVerdict.ok || positionVerdict == InstallVerdict.unchecked && firstOnFloor);

  /// The `checks` body of `POST /markers/:code/confirm-install`.
  Map<String, dynamic> toChecksJson() => {
        'code': rightBoard,
        if (scalePct != null) 'scalePct': double.parse(scalePct!.toStringAsFixed(1)),
        if (positionM != null) 'positionM': double.parse(positionM!.toStringAsFixed(3)),
        if (tiltDeg != null) 'tiltDeg': double.parse(tiltDeg!.toStringAsFixed(1)),
      };
}

/// The installer's self-check (docs/ar-markers-and-qr.md §5.3, I3Check).
/// Runs the flowchart in order and stops where the installer has to act:
///
/// 1. **Code** — the expected board for this stop? Otherwise a swap.
/// 2. **Print scale** — the QR edge from depth within ±2%; without depth,
///    a tap to confirm the 100 mm line.
/// 3. **Position** — locked session: ≤ 3 cm ok, 3–10 cm keep as built
///    (Derived) or move, > 10 cm wrong spot. First boards on a floor: the
///    measured distance to another installed board vs plan, within 2 cm.
///    The very first board can't be checked until the second goes up.
/// 4. **Tilt** — ≤ 3°, otherwise "Straighten it".
class InstallCheck {
  const InstallCheck();

  static const scaleTolerancePct = 2.0;
  static const positionOkM = 0.03;
  static const positionKeepM = 0.10;
  static const pairToleranceM = 0.02;
  static const tiltMaxDeg = 3.0;

  InstallCheckResult run(InstallCheckInput input) {
    final expected = MarkerCode.normalize(input.expectedCode) ?? input.expectedCode.trim().toUpperCase();
    final scanned = MarkerCode.normalize(input.scannedCode) ?? input.scannedCode.trim().toUpperCase();

    // 1. Right board?
    if (expected != scanned) {
      return InstallCheckResult(
        rightBoard: false,
        swappedWithLabel: input.scannedLabel ?? MarkerCode.display(scanned),
        scaleOk: false,
        positionVerdict: InstallVerdict.unchecked,
        tiltOk: false,
        firstOnFloor: false,
        messageKeys: const [InstallCheckMessage.swap],
      );
    }
    final messages = <String>[InstallCheckMessage.codeOk];

    // 2. Print scale.
    double? scalePct;
    final edge = input.qrEdgeMm;
    if (edge != null && input.printedQrMm > 0) {
      scalePct = edge / input.printedQrMm * 100;
      if ((scalePct - 100).abs() > scaleTolerancePct) {
        return InstallCheckResult(
          rightBoard: true,
          scalePct: scalePct,
          scaleOk: false,
          positionVerdict: InstallVerdict.unchecked,
          tiltOk: true,
          firstOnFloor: false,
          messageKeys: [...messages, InstallCheckMessage.scaleOff],
        );
      }
      messages.add(InstallCheckMessage.scaleOk);
    } else if (!input.manualScaleConfirmed) {
      return InstallCheckResult(
        rightBoard: true,
        scaleOk: false,
        scaleNeedsConfirm: true,
        positionVerdict: InstallVerdict.unchecked,
        tiltOk: true,
        firstOnFloor: false,
        messageKeys: [...messages, InstallCheckMessage.scaleConfirm],
      );
    } else {
      messages.add(InstallCheckMessage.scaleConfirmed);
    }

    // 3. Position.
    var verdict = InstallVerdict.unchecked;
    double? positionM;
    String? pairLabel;
    var firstOnFloor = false;
    var expectActive = false;
    final measuredTile = input.measuredPosTile;
    final pair = input.pair;
    final measuredAr = input.measuredPosAr;
    if (input.sessionLocked && measuredTile != null) {
      positionM = measuredTile.distanceTo(input.plannedPosTile);
      if (positionM <= positionOkM) {
        verdict = InstallVerdict.ok;
        expectActive = true;
        messages.add(InstallCheckMessage.positionOk);
      } else if (positionM <= positionKeepM) {
        verdict = InstallVerdict.keepAsBuilt;
        messages.add(InstallCheckMessage.keepAsBuilt);
      } else {
        verdict = InstallVerdict.wrongSpot;
        messages.add(InstallCheckMessage.wrongSpot);
      }
    } else if (pair != null && measuredAr != null) {
      final measured = measuredAr.distanceTo(pair.observedAr);
      final planned = input.plannedPosTile.distanceTo(pair.plannedPosTile);
      positionM = (measured - planned).abs();
      pairLabel = pair.label;
      if (positionM <= pairToleranceM) {
        verdict = InstallVerdict.ok;
        expectActive = true;
        messages.add(InstallCheckMessage.bothActive);
      } else {
        verdict = InstallVerdict.wrongSpot;
        messages.add(InstallCheckMessage.wrongSpot);
      }
    } else {
      firstOnFloor = true;
      messages.add(InstallCheckMessage.firstOnFloor);
    }

    // 4. Tilt — skipped for a board in the wrong spot: it has to move first.
    double? tilt;
    var tiltOk = true;
    if (verdict != InstallVerdict.wrongSpot && input.mounting != 'floor') {
      tilt = input.tiltDeg ?? _tiltFrom(input.boardUpAr, input.boardNormalAr);
      if (tilt != null) {
        tiltOk = tilt <= tiltMaxDeg;
        messages.add(tiltOk ? InstallCheckMessage.level : InstallCheckMessage.straighten);
      }
    }

    return InstallCheckResult(
      rightBoard: true,
      scalePct: scalePct,
      scaleOk: true,
      positionM: positionM,
      positionVerdict: verdict,
      pairLabel: pairLabel,
      tiltDeg: tilt,
      tiltOk: tiltOk,
      firstOnFloor: firstOnFloor,
      expectActive: expectActive && tiltOk,
      messageKeys: List.unmodifiable(messages),
    );
  }

  /// A wall board's tilt: the larger of its rotation off vertical (the QR's
  /// up vs gravity) and its lean (the normal off horizontal).
  static double? _tiltFrom(Vec3? up, Vec3? normal) {
    double? rotation;
    double? lean;
    if (up != null && up.length > 1e-9) {
      final u = up.normalized;
      rotation = radToDeg(math.acos(u.y.clamp(-1.0, 1.0).toDouble()));
    }
    if (normal != null && normal.length > 1e-9) {
      final n = normal.normalized;
      lean = radToDeg(math.asin(n.y.abs().clamp(0.0, 1.0).toDouble()));
    }
    if (rotation == null) return lean;
    if (lean == null) return rotation;
    return math.max(rotation, lean);
  }
}
