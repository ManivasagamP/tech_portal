import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ar/alignment_estimator.dart';
import '../core/ar/install_check.dart';
import '../core/ar/vec.dart';
import 'ar_catalog_controller.dart';
import 'ar_session_controller.dart';
import 'ar_view_models.dart';

/// Installer flow (docs/ar-markers-and-qr.md §5.3, I1Run → I2Guide →
/// I3Check). The run is the floor's boards still waiting to go up, in
/// walking order; each stop's self-check runs the pure [InstallCheck] on
/// what the phone measured when the board was scanned. The installer never
/// measures anything.

class ArInstallStop {
  const ArInstallStop({required this.marker, required this.order, required this.done, this.legFromPreviousM});
  final ArMarkerInfo marker;
  final int order;
  final bool done;

  /// Walking distance (straight line) from the previous stop.
  final double? legFromPreviousM;
}

class ArInstallRun {
  const ArInstallRun({
    required this.floor,
    required this.stops,
  });

  final ArFloorContext floor;

  /// Walking order: done stops first (in the order they went up), then the
  /// rest by a nearest-neighbour tour from the last done board.
  final List<ArInstallStop> stops;

  int get total => stops.length;
  int get doneCount => stops.where((s) => s.done).length;
  ArInstallStop? get next {
    for (final s in stops) {
      if (!s.done) return s;
    }
    return null;
  }

  /// About 3 minutes a board (walk, stick, scan), for "~12 min left".
  int get minutesLeft => (total - doneCount) * 3;
}

/// Boards awaiting install on a floor: planned, printed, or installed but
/// not yet confirmed Active. Active boards count as done.
final arInstallRunProvider = FutureProvider.autoDispose.family<ArInstallRun, String>((ref, floorId) async {
  final gateway = ref.watch(arGatewayProvider);
  ref.watch(arInstallTickProvider);
  final floor = await gateway.floorContext(floorId);
  final done = <ArMarkerInfo>[];
  final pending = <ArMarkerInfo>[];
  final confirmed = ref.read(arInstallConfirmedProvider);
  for (final m in floor.markers) {
    if (m.isSpare || m.isRetired) continue;
    final isDone = m.status == 'active' || confirmed.contains(m.code);
    if (isDone) {
      done.add(m);
    } else if (m.status == 'planned' || m.status == 'printed' || m.status == 'installed') {
      pending.add(m);
    }
  }
  final stops = <ArInstallStop>[];
  var order = 1;
  Vec3? prev;
  for (final m in done) {
    stops.add(ArInstallStop(marker: m, order: order++, done: true, legFromPreviousM: prev?.distanceXzTo(m.posTile)));
    prev = m.posTile;
  }
  // Nearest-neighbour tour, starting from the last board that went up.
  final left = [...pending];
  var here = prev ?? (left.isEmpty ? null : left.first.posTile);
  while (left.isNotEmpty && here != null) {
    final from = here;
    left.sort((a, b) => a.posTile.distanceXzTo(from).compareTo(b.posTile.distanceXzTo(from)));
    final m = left.removeAt(0);
    stops.add(ArInstallStop(marker: m, order: order++, done: false, legFromPreviousM: prev?.distanceXzTo(m.posTile)));
    prev = m.posTile;
    here = m.posTile;
  }
  return ArInstallRun(floor: floor, stops: stops);
});

/// Bumped after a confirm so the run list re-reads.
final arInstallTickProvider = StateProvider<int>((ref) => 0);

/// Codes confirmed on this phone this run (queued confirms included), so
/// the list moves on even before the server's status arrives.
final arInstallConfirmedProvider = StateProvider<Set<String>>((ref) => <String>{});

enum ArInstallPhase { guide, scanning, result, saving, done }

class ArInstallState {
  const ArInstallState({
    this.phase = ArInstallPhase.guide,
    this.expectedCode,
    this.result,
    this.sighting,
    this.manualScaleConfirmed = false,
    this.photoPath,
    this.queued = false,
    this.errorKey,
    this.keptAsBuilt = false,
    this.checkedInMs,
  });

  final ArInstallPhase phase;
  final String? expectedCode;
  final InstallCheckResult? result;
  final ArMarkerSighting? sighting;
  final bool manualScaleConfirmed;
  final String? photoPath;
  final bool queued;
  final String? errorKey;
  final bool keptAsBuilt;

  /// "Checked in 2 seconds."
  final int? checkedInMs;

  ArInstallState copyWith({
    ArInstallPhase? phase,
    String? expectedCode,
    InstallCheckResult? result,
    bool clearResult = false,
    ArMarkerSighting? sighting,
    bool? manualScaleConfirmed,
    String? photoPath,
    bool? queued,
    String? errorKey,
    bool clearError = false,
    bool? keptAsBuilt,
    int? checkedInMs,
  }) => ArInstallState(
    phase: phase ?? this.phase,
    expectedCode: expectedCode ?? this.expectedCode,
    result: clearResult ? null : (result ?? this.result),
    sighting: sighting ?? this.sighting,
    manualScaleConfirmed: manualScaleConfirmed ?? this.manualScaleConfirmed,
    photoPath: photoPath ?? this.photoPath,
    queued: queued ?? this.queued,
    errorKey: clearError ? null : (errorKey ?? this.errorKey),
    keptAsBuilt: keptAsBuilt ?? this.keptAsBuilt,
    checkedInMs: checkedInMs ?? this.checkedInMs,
  );
}

class ArInstallController extends AutoDisposeNotifier<ArInstallState> {
  var _lastMarkerSeq = -1;
  var _disposed = false;
  DateTime? _scanStartedAt;

  ArSessionController get _session => ref.read(arSessionProvider.notifier);
  ArSessionState get _s => ref.read(arSessionProvider);

  @override
  ArInstallState build() {
    ref.onDispose(() => _disposed = true);
    ref.listen<ArSessionState>(arSessionProvider, (prev, next) {
      final m = next.lastMarker;
      if (m == null || m.seq == _lastMarkerSeq) return;
      _lastMarkerSeq = m.seq;
      if (state.phase == ArInstallPhase.scanning) _onSighting(m);
    });
    return const ArInstallState();
  }

  void _set(ArInstallState next) {
    if (_disposed) return;
    state = next;
  }

  void begin(String code) => _set(ArInstallState(expectedCode: code));

  void startScan() {
    _scanStartedAt = DateTime.now();
    _set(state.copyWith(phase: ArInstallPhase.scanning, clearResult: true, clearError: true));
  }

  void backToGuide() => _set(state.copyWith(phase: ArInstallPhase.guide, clearResult: true));

  /// Demo: the board goes up and is scanned from a metre away.
  void demoScan({bool swap = false}) {
    final director = _session.director;
    final floor = _s.floor;
    final code = state.expectedCode;
    if (director == null || floor == null || code == null) return;
    final expected = floor.markerByCode(code);
    if (expected == null) return;
    ArMarkerInfo target = expected;
    if (swap) {
      for (final m in floor.markers) {
        if (m.code != code && (m.status == 'printed' || m.status == 'planned')) {
          target = m;
          break;
        }
      }
    }
    // Stuck 1 cm from the plan: a realistic, passing install.
    final pos = Vec3(target.posTile.x + 0.008, target.posTile.y + 0.004, target.posTile.z + 0.006);
    _session.injectDemoMarker(director.sightingAt(target.code, pos, target.normalTile, scalePct: 100.2));
  }

  void _onSighting(ArMarkerSighting m) {
    final code = state.expectedCode;
    final floor = _s.floor;
    if (code == null || floor == null || m.code == null) return;
    final expected = floor.markerByCode(code);
    if (expected == null) return;
    // An active board seen while scanning just strengthens the fit (setup
    // handles it); only an awaited board — this one or a swap — is checked.
    final scanned = floor.markerByCode(m.code!);
    if (m.code != code && scanned != null && scanned.usableForAlignment && scanned.status == 'active') return;
    _set(state.copyWith(sighting: m));
    _run(expected, m, scanned);
  }

  void _run(ArMarkerInfo expected, ArMarkerSighting m, ArMarkerInfo? scanned) {
    final s = _s;
    final fit = s.fit;
    final locked = s.isLocked;
    InstallPairRef? pair;
    if (!locked) {
      for (final o in s.observations) {
        if (o is MarkerObs && o.id != expected.code) {
          final other = s.floor?.markerByCode(o.id);
          pair = InstallPairRef(label: other?.label ?? o.id, plannedPosTile: o.bTile, observedAr: o.aAr);
          break;
        }
      }
    }
    final input = InstallCheckInput(
      expectedCode: expected.code,
      scannedCode: m.code!,
      scannedLabel: scanned?.label,
      plannedPosTile: expected.posTile,
      qrEdgeMm: m.qrEdgeMm,
      manualScaleConfirmed: state.manualScaleConfirmed,
      sessionLocked: locked,
      measuredPosTile: locked && fit != null ? fit.arToTile(m.centreAr) : null,
      measuredPosAr: m.centreAr,
      pair: pair,
      boardNormalAr: m.normalAr,
      mounting: expected.mounting,
    );
    final result = const InstallCheck().run(input);
    final ms = _scanStartedAt == null ? null : DateTime.now().difference(_scanStartedAt!).inMilliseconds;
    _set(state.copyWith(phase: ArInstallPhase.result, result: result, checkedInMs: ms));
    if (result.allGood) unawaited(confirm());
  }

  /// "Tap to confirm the 100 mm line" (no depth sensor), then re-check.
  void confirmManualScale() {
    final m = state.sighting;
    final floor = _s.floor;
    final code = state.expectedCode;
    _set(state.copyWith(manualScaleConfirmed: true));
    if (m == null || floor == null || code == null) return;
    final expected = floor.markerByCode(code);
    if (expected == null) return;
    _run(expected, m, floor.markerByCode(m.code ?? ''));
  }

  /// "Keep as built (Derived)": confirm at the measured spot.
  Future<void> keepAsBuilt() async {
    _set(state.copyWith(keptAsBuilt: true));
    await confirm(asBuilt: true);
  }

  /// Confirms the install: an automatic photo with the overlay, then
  /// `confirm-install` through the offline queue. The server repeats the
  /// checks it can and decides Installed vs Active.
  Future<void> confirm({bool asBuilt = false}) async {
    final code = state.expectedCode;
    final floor = _s.floor;
    final result = state.result;
    final m = state.sighting;
    final gateway = _session.gateway;
    final buildId = floor?.primaryBuildId;
    if (code == null || floor == null || result == null || gateway == null || buildId == null) return;
    _set(state.copyWith(phase: ArInstallPhase.saving, clearError: true));
    final photo = await _session.capture();
    final fit = _s.fit;
    Vec3? pos;
    Vec3? normal;
    if (m != null && fit != null && fit.isPlaced && (asBuilt || _s.isLocked)) {
      pos = fit.arToTile(m.centreAr);
      final n = fit.dirArToTile(m.normalAr);
      normal = Vec3(n.x, 0, n.z).normalized;
    }
    final write = await gateway.confirmInstall(
      code: code,
      buildId: buildId,
      checks: ArInstallChecks(
        code: result.rightBoard,
        scalePct: result.scalePct == null ? null : double.parse(result.scalePct!.toStringAsFixed(1)),
        positionM: result.positionM == null ? null : double.parse(result.positionM!.toStringAsFixed(3)),
        tiltDeg: result.tiltDeg == null ? null : double.parse(result.tiltDeg!.toStringAsFixed(1)),
      ),
      posTile: pos,
      normalTile: normal,
      photoPath: photo,
    );
    if (_disposed) return;
    if (write.ok) {
      ref.read(arInstallConfirmedProvider.notifier).state = {...ref.read(arInstallConfirmedProvider), code};
      ref.read(arInstallTickProvider.notifier).state++;
      _set(state.copyWith(phase: ArInstallPhase.done, photoPath: photo, queued: write.queued && !write.synced));
    } else {
      _set(state.copyWith(phase: ArInstallPhase.result, errorKey: 'ar.install.confirm_failed'));
    }
  }
}

final arInstallProvider = NotifierProvider.autoDispose<ArInstallController, ArInstallState>(ArInstallController.new);

/// Straight-line distance from the camera (once placed) to a stop.
double? arDistanceToStop(ArSessionState s, ArMarkerInfo m) {
  final cam = s.cameraTile;
  if (cam == null) return null;
  return math.max(0, cam.distanceXzTo(m.posTile));
}
