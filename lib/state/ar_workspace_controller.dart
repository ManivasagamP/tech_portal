import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ar/feature_state.dart';
import '../core/c2o/c2o_asset_resolver.dart';
import '../core/ar/vec.dart';
import '../domain/snag.dart';
import 'ar_session_controller.dart';
import 'ar_view_models.dart';
import 'auth_controller.dart';
import 'providers.dart';
import 'snag_controller.dart';

/// The AR workspace (docs/ar-setup-and-gamma-parity.md §2.9, AR-58): what a
/// tap does (mode), how it selects (single, multi, lasso), what is shown
/// (layers), and the progress status of what is selected (AR-50, four-eyes).
/// One state for both layouts: the iPad rails and the phone's tab bar and
/// sheet render the same fields.
enum ArMode { locate, verify, progress, snags, forms }

enum ArSelectMode { single, multi, lasso }

enum ArPanel { none, menu, layers, more }

enum ArColourBy { discipline, progress, system, snags }

class ArLayerState {
  const ArLayerState({
    this.mep = true,
    this.structure = true,
    this.architecture = true,
    this.pipes = true,
    this.ducts = true,
    this.equipment = true,
    this.cableTrays = true,
    this.wallsAsEdges = true,
    this.phaseExisting = true,
    this.phaseNew = true,
    this.phaseDemolition = false,
    this.colourBy = ArColourBy.discipline,
    this.opacity = 0.7,
    this.section = false,
  });

  final bool mep;
  final bool structure;
  final bool architecture;
  final bool pipes;
  final bool ducts;
  final bool equipment;
  final bool cableTrays;
  final bool wallsAsEdges;
  final bool phaseExisting;
  final bool phaseNew;
  final bool phaseDemolition;
  final ArColourBy colourBy;
  final double opacity;

  /// A horizontal cut 1.2 m above the finished floor, like the web's cut plan.
  final bool section;

  ArLayerState copyWith({
    bool? mep,
    bool? structure,
    bool? architecture,
    bool? pipes,
    bool? ducts,
    bool? equipment,
    bool? cableTrays,
    bool? wallsAsEdges,
    bool? phaseExisting,
    bool? phaseNew,
    bool? phaseDemolition,
    ArColourBy? colourBy,
    double? opacity,
    bool? section,
  }) => ArLayerState(
    mep: mep ?? this.mep,
    structure: structure ?? this.structure,
    architecture: architecture ?? this.architecture,
    pipes: pipes ?? this.pipes,
    ducts: ducts ?? this.ducts,
    equipment: equipment ?? this.equipment,
    cableTrays: cableTrays ?? this.cableTrays,
    wallsAsEdges: wallsAsEdges ?? this.wallsAsEdges,
    phaseExisting: phaseExisting ?? this.phaseExisting,
    phaseNew: phaseNew ?? this.phaseNew,
    phaseDemolition: phaseDemolition ?? this.phaseDemolition,
    colourBy: colourBy ?? this.colourBy,
    opacity: opacity ?? this.opacity,
    section: section ?? this.section,
  );
}

class ArWorkspaceState {
  const ArWorkspaceState({
    this.mode = ArMode.locate,
    this.selectMode = ArSelectMode.single,
    this.selection = const [],
    this.panel = ArPanel.none,
    this.layers = const ArLayerState(),
    this.progress = const ArProgressSnapshot(),
    this.progressLoaded = false,
    this.progressBusy = false,
    this.rejections = const [],
    this.planInCorner = false,
    this.torch = false,
    this.measuring = false,
    this.measureFrom,
    this.measureM,
    this.lassoBusy = false,
    this.picking = false,
    this.lastPickMissed = false,
    this.savedViews = 0,
    this.snagPins = const [],
    this.verify,
    this.mappingConfirmed = true,
  });

  final ArMode mode;
  final ArSelectMode selectMode;
  final List<ArFeature> selection;
  final ArPanel panel;
  final ArLayerState layers;
  final ArProgressSnapshot progress;
  final bool progressLoaded;
  final bool progressBusy;

  /// The server (or the client's UX check) refused these: shown on the card.
  final List<ArProgressRejection> rejections;
  final bool planInCorner;
  final bool torch;
  final bool measuring;
  final ArPickHit? measureFrom;
  final double? measureM;
  final bool lassoBusy;
  final bool picking;
  final bool lastPickMissed;
  final int savedViews;

  /// Live snags on this floor that map to a modelled element.
  final List<ArSnagPin> snagPins;

  /// Verify mode's AR pre-check for the selected asset (M6).
  final ArVerifyCheck? verify;

  /// "This is the element in the model" — a human confirmation of the
  /// asset ↔ element mapping (§1.2), on by default, one tap to clear.
  final bool mappingConfirmed;

  ArFeature? get primary => selection.isEmpty ? null : selection.first;

  ArWorkspaceState copyWith({
    ArMode? mode,
    ArSelectMode? selectMode,
    List<ArFeature>? selection,
    ArPanel? panel,
    ArLayerState? layers,
    ArProgressSnapshot? progress,
    bool? progressLoaded,
    bool? progressBusy,
    List<ArProgressRejection>? rejections,
    bool? planInCorner,
    bool? torch,
    bool? measuring,
    ArPickHit? measureFrom,
    bool clearMeasure = false,
    double? measureM,
    bool? lassoBusy,
    bool? picking,
    bool? lastPickMissed,
    int? savedViews,
    List<ArSnagPin>? snagPins,
    ArVerifyCheck? verify,
    bool clearVerify = false,
    bool? mappingConfirmed,
  }) => ArWorkspaceState(
    mode: mode ?? this.mode,
    selectMode: selectMode ?? this.selectMode,
    selection: selection ?? this.selection,
    panel: panel ?? this.panel,
    layers: layers ?? this.layers,
    progress: progress ?? this.progress,
    progressLoaded: progressLoaded ?? this.progressLoaded,
    progressBusy: progressBusy ?? this.progressBusy,
    rejections: rejections ?? this.rejections,
    planInCorner: planInCorner ?? this.planInCorner,
    torch: torch ?? this.torch,
    measuring: measuring ?? this.measuring,
    measureFrom: clearMeasure ? null : (measureFrom ?? this.measureFrom),
    measureM: clearMeasure ? null : (measureM ?? this.measureM),
    lassoBusy: lassoBusy ?? this.lassoBusy,
    picking: picking ?? this.picking,
    lastPickMissed: lastPickMissed ?? this.lastPickMissed,
    savedViews: savedViews ?? this.savedViews,
    snagPins: snagPins ?? this.snagPins,
    verify: clearVerify ? null : (verify ?? this.verify),
    mappingConfirmed: mappingConfirmed ?? this.mappingConfirmed,
  );
}

/// M6's location check: where the scanned tag *is* against where the model
/// says the asset is, with the tolerance of today's lock. Never a
/// millimetre claim: "12 cm from its modelled position".
class ArVerifyCheck {
  const ArVerifyCheck({
    required this.assetId,
    this.offsetM,
    this.toleranceM = 0.35,
    this.tagAssetId,
    this.tagMatches,
    this.checking = false,
  });

  final String assetId;
  final double? offsetM;
  final double toleranceM;
  final String? tagAssetId;
  final bool? tagMatches;
  final bool checking;

  bool get measured => offsetM != null;
  bool get consistent => offsetM != null && offsetM! <= toleranceM;
  String get result => !measured ? 'unchecked' : (consistent ? 'consistent' : 'offset');
}

class ArSnagPin {
  const ArSnagPin({required this.snagId, required this.title, required this.feature});
  final String snagId;
  final String title;
  final ArFeature feature;
}

/// What the selection adds up to: "3 selected · CHW supply", "42.6 m of pipe
/// · 2 isolation valves". Quantities come from the geometry (AR-50).
class ArSelectionSummary {
  const ArSelectionSummary({
    required this.count,
    this.systemName,
    this.runLengthM = 0,
    this.valves = 0,
    this.equipment = 0,
  });

  final int count;
  final String? systemName;
  final double runLengthM;
  final int valves;
  final int equipment;

  static ArSelectionSummary of(List<ArFeature> selection) {
    var run = 0.0;
    var valves = 0;
    var equipment = 0;
    final systems = <String>{};
    for (final f in selection) {
      if (f.isRun) {
        run += f.extentM;
      } else if (f.isValve) {
        valves++;
      } else {
        equipment++;
      }
      final sys = f.systemName ?? f.systemGlobalId;
      if (sys != null) systems.add(sys);
    }
    return ArSelectionSummary(
      count: selection.length,
      systemName: systems.length == 1 ? selection.map((f) => f.systemName).whereType<String>().firstOrNullSafe : null,
      runLengthM: run,
      valves: valves,
      equipment: equipment,
    );
  }
}

extension _FirstOrNullSafe<T> on Iterable<T> {
  T? get firstOrNullSafe {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

class ArWorkspaceController extends AutoDisposeNotifier<ArWorkspaceState> {
  var _disposed = false;
  String? _progressFor;
  var _lastMarkerSeq = -1;
  ArFloorContext? _floorSeen;

  ArSessionController get _session => ref.read(arSessionProvider.notifier);
  ArSessionState get _s => ref.read(arSessionProvider);

  @override
  ArWorkspaceState build() {
    ref.onDispose(() => _disposed = true);
    ref.listen<ArSessionState>(arSessionProvider, (prev, next) {
      // A restarted session (Demo toggle, retry) brings a new floor pack:
      // nothing selected or measured on the old one carries over.
      final floor = next.floor;
      if (floor != null && !identical(floor, _floorSeen)) {
        if (_floorSeen != null) {
          _progressFor = null;
          _set(ArWorkspaceState(layers: state.layers));
        }
        _floorSeen = floor;
      }
      // Entering work with a target: Locate is the job (§1.1).
      if (prev?.stage != ArSessionStage.work && next.stage == ArSessionStage.work) {
        unawaited(_pushLayers());
        unawaited(_pushFeatureState());
        unawaited(_loadSnagPins());
        if (next.target != null && state.selection.isEmpty) {
          _set(state.copyWith(mode: ArMode.locate, selection: [next.target!]));
        }
      }
      if (prev?.features.length != next.features.length) unawaited(_loadSnagPins());
      // Verify: any QR that isn't a board is an asset tag being checked.
      final m = next.lastMarker;
      if (m != null && m.seq != _lastMarkerSeq) {
        _lastMarkerSeq = m.seq;
        if (m.code == null && state.mode == ArMode.verify && next.stage == ArSessionStage.work) {
          unawaited(_checkTag(m));
        }
      }
    });
    final s = ref.read(arSessionProvider);
    return ArWorkspaceState(selection: s.target == null ? const [] : [s.target!]);
  }

  void _set(ArWorkspaceState next) {
    if (_disposed) return;
    state = next;
  }

  String get _me {
    if (_s.demo) return 'demo-me';
    return ref.read(authControllerProvider).session?.userId ?? '';
  }

  // ------------------------------------------------------------ modes

  void setMode(ArMode m) {
    _set(state.copyWith(mode: m, panel: ArPanel.none, rejections: const [], measuring: false, clearMeasure: true, clearVerify: true));
    if (m == ArMode.progress) {
      unawaited(loadProgress());
      if (state.layers.colourBy != ArColourBy.progress) {
        setLayers(state.layers.copyWith(colourBy: ArColourBy.progress));
      }
    } else if (m == ArMode.snags) {
      unawaited(_loadSnagPins());
    }
    unawaited(_pushFeatureState());
  }

  void setSelectMode(ArSelectMode m) => _set(state.copyWith(selectMode: m));

  void openPanel(ArPanel p) => _set(state.copyWith(panel: state.panel == p ? ArPanel.none : p));

  void closePanel() => _set(state.copyWith(panel: ArPanel.none));

  // -------------------------------------------------------- selection

  /// A tap on the view at ([x], [y]) in logical pixels (the engine's
  /// `pick` takes view pixels). [demoHit] is Demo mode's own hit test.
  Future<void> tap(double x, double y, {ArFeature? demoHit}) async {
    if (state.measuring) {
      await _measureTap(x, y, demoHit: demoHit);
      return;
    }
    _set(state.copyWith(picking: true, lastPickMissed: false));
    ArFeature? f = demoHit;
    if (f == null && !_s.demo) {
      final hit = await _session.pick(x, y);
      f = hit == null ? null : _featureFor(hit);
    }
    if (_disposed) return;
    if (f == null) {
      _set(state.copyWith(picking: false, lastPickMissed: true));
      return;
    }
    final hitFeature = f;
    final List<ArFeature> next;
    if (state.selectMode == ArSelectMode.single) {
      next = [hitFeature];
    } else if (state.selection.any((x) => _same(x, hitFeature))) {
      next = state.selection.where((x) => !_same(x, hitFeature)).toList();
    } else {
      next = [...state.selection, hitFeature];
    }
    _set(state.copyWith(selection: next, picking: false, rejections: const []));
    unawaited(_pushFeatureState());
  }

  /// Lasso: samples the drawn polygon (view pixels) on a grid and picks at
  /// each sample, so the engine needs no projection API. Capped at about 120
  /// picks so a huge lasso still finishes in a moment.
  Future<void> lasso(List<(double, double)> polygon, {List<ArFeature> demoHits = const []}) async {
    if (polygon.length < 3 && demoHits.isEmpty) return;
    _set(state.copyWith(lassoBusy: true));
    final found = <ArFeature>[...demoHits];
    if (!_s.demo && polygon.length >= 3) {
      var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
      for (final (x, y) in polygon) {
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
      const maxSamples = 120;
      final area = math.max(1.0, (maxX - minX) * (maxY - minY));
      final step = math.max(24.0, math.sqrt(area / maxSamples));
      for (var y = minY; y <= maxY; y += step) {
        for (var x = minX; x <= maxX; x += step) {
          if (!_inside(polygon, x, y)) continue;
          final hit = await _session.pick(x, y);
          if (_disposed) return;
          final f = hit == null ? null : _featureFor(hit);
          if (f != null && !found.any((e) => _same(e, f))) found.add(f);
        }
      }
    }
    final merged = state.selectMode == ArSelectMode.lasso && state.selection.isNotEmpty
        ? [...state.selection, ...found.where((f) => !state.selection.any((s) => _same(s, f)))]
        : found;
    _set(state.copyWith(selection: merged, lassoBusy: false, rejections: const []));
    unawaited(_pushFeatureState());
  }

  void clearSelection() {
    _set(state.copyWith(selection: const [], rejections: const []));
    unawaited(_pushFeatureState());
  }

  /// Select a whole system from the current element ("Trace", §3).
  void selectSystemOf(ArFeature f) {
    final sys = f.systemGlobalId;
    if (sys == null) return;
    final all = _s.features.where((x) => x.systemGlobalId == sys && x.buildId == f.buildId).toList();
    _set(state.copyWith(selection: all, selectMode: ArSelectMode.multi));
    unawaited(_pushFeatureState());
  }

  /// Make [f] the Locate target (pulsing, drawn through walls).
  Future<void> locate(ArFeature f) async {
    await _session.setTargetFeature(f);
    _set(state.copyWith(mode: ArMode.locate, selection: [f]));
    unawaited(_pushFeatureState());
  }

  ArFeature? _featureFor(ArPickHit hit) {
    for (final f in _s.features) {
      if (f.featureId == hit.featureId && (hit.buildId == null || hit.buildId == f.buildId)) return f;
    }
    return null;
  }

  static bool _same(ArFeature a, ArFeature b) => a.featureId == b.featureId && a.buildId == b.buildId;

  static bool _inside(List<(double, double)> poly, double x, double y) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final (xi, yi) = poly[i];
      final (xj, yj) = poly[j];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / ((yj - yi) == 0 ? 1e-9 : (yj - yi)) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }

  // ------------------------------------------------------------- measure

  void toggleMeasure() => _set(state.copyWith(measuring: !state.measuring, clearMeasure: true));

  Future<void> _measureTap(double x, double y, {ArFeature? demoHit}) async {
    ArPickHit? hit;
    if (_s.demo && demoHit != null) {
      hit = ArPickHit(featureId: demoHit.featureId, buildId: demoHit.buildId, hitTile: demoHit.centre);
    } else {
      hit = await _session.pick(x, y);
    }
    if (_disposed || hit == null || hit.hitTile == null) {
      _set(state.copyWith(lastPickMissed: true));
      return;
    }
    final from = state.measureFrom;
    if (from == null || from.hitTile == null || state.measureM != null) {
      // First point (or a new measurement after a finished one).
      _set(state.copyWith(clearMeasure: true));
      _set(state.copyWith(measureFrom: hit, lastPickMissed: false));
      return;
    }
    _set(state.copyWith(measureM: from.hitTile!.distanceTo(hit.hitTile!), lastPickMissed: false));
  }

  // -------------------------------------------------------------- layers

  void setLayers(ArLayerState l) {
    _set(state.copyWith(layers: l));
    unawaited(_pushLayers());
    unawaited(_pushFeatureState());
  }

  void toggleSection() => setLayers(state.layers.copyWith(section: !state.layers.section));

  void setOpacity(double v) {
    _set(state.copyWith(layers: state.layers.copyWith(opacity: v.clamp(0.1, 1).toDouble())));
    unawaited(_pushLayers());
  }

  void togglePlanInCorner() => _set(state.copyWith(planInCorner: !state.planInCorner));

  void toggleTorch() => _set(state.copyWith(torch: !state.torch));

  void saveView() => _set(state.copyWith(savedViews: state.savedViews + 1));

  Future<void> _pushLayers() async {
    final l = state.layers;
    final floor = _s.floor;
    final datum = floor == null ? 0.0 : floor.floorDatumY + floor.floorFinishOffsetM;
    await _session.setLayers(
      mep: l.mep,
      structure: l.structure,
      architecture: l.architecture,
      opacity: l.opacity,
      sectionY: l.section ? datum + 1.2 : null,
    );
  }

  // ------------------------------------------------------------ progress

  Future<void> loadProgress({bool force = false}) async {
    final floor = _s.floor;
    final gateway = _session.gateway;
    if (floor == null || gateway == null) return;
    if (!force && _progressFor == floor.floorId && state.progressLoaded) return;
    _progressFor = floor.floorId;
    try {
      final snapshot = await gateway.progress(floor.floorId);
      if (_disposed) return;
      _set(state.copyWith(progress: snapshot, progressLoaded: true));
      unawaited(_pushFeatureState());
    } catch (_) {
      _set(state.copyWith(progressLoaded: true));
    }
  }

  /// The client-side four-eyes preview (UX only; the server decides): which
  /// selected elements a "Verified" from *me* would be refused for, and why.
  List<ArProgressRejection> verifyBlockers() {
    final me = _me;
    final out = <ArProgressRejection>[];
    for (final f in state.selection) {
      final e = state.progress.entries[f.globalId];
      final status = e?.status ?? ArProgressStatus.notStarted;
      if (status == ArProgressStatus.verified) continue;
      if (status != ArProgressStatus.installed) {
        out.add(ArProgressRejection(globalId: f.globalId, reason: 'NOT_INSTALLED'));
      } else if (e?.installedBy != null && e!.installedBy == me) {
        out.add(ArProgressRejection(globalId: f.globalId, reason: 'SECOND_PERSON_REQUIRED'));
      }
    }
    return out;
  }

  /// Marks the selection. Returns what happened, for the card's message.
  Future<ArProgressWriteResult?> setStatus(ArProgressStatus status, {String? note}) async {
    final floor = _s.floor;
    final gateway = _session.gateway;
    if (floor == null || gateway == null || state.selection.isEmpty) return null;
    final ids = state.selection.map((f) => f.globalId).toSet().toList();
    _set(state.copyWith(progressBusy: true, rejections: const []));
    final result = await gateway.setProgress(floorId: floor.floorId, globalIds: ids, status: status, note: note);
    if (_disposed) return result;
    // Optimistic: what the server accepted (or what is queued) shows now.
    final rejected = result.rejected.map((r) => r.globalId).toSet();
    final entries = {...state.progress.entries};
    final now = DateTime.now();
    for (final id in ids) {
      if (rejected.contains(id)) continue;
      final prev = entries[id];
      entries[id] = ArProgressEntry(
        globalId: id,
        status: status,
        assetId: prev?.assetId,
        installedBy: status == ArProgressStatus.installed ? _me : prev?.installedBy,
        installedAt: status == ArProgressStatus.installed ? now : prev?.installedAt,
        verifiedBy: status == ArProgressStatus.verified ? _me : prev?.verifiedBy,
        verifiedAt: status == ArProgressStatus.verified ? now : prev?.verifiedAt,
        note: note ?? prev?.note,
      );
    }
    _set(state.copyWith(
      progress: _recount(entries, state.progress.total),
      progressBusy: false,
      rejections: result.rejected,
    ));
    unawaited(_pushFeatureState());
    return result;
  }

  ArProgressSnapshot _recount(Map<String, ArProgressEntry> entries, int total) {
    var installed = 0, verified = 0, issue = 0;
    for (final e in entries.values) {
      switch (e.status) {
        case ArProgressStatus.installed:
          installed++;
        case ArProgressStatus.verified:
          verified++;
        case ArProgressStatus.issue:
          issue++;
        case ArProgressStatus.notStarted:
          break;
      }
    }
    final features = _s.features.length;
    return ArProgressSnapshot(
      entries: entries,
      total: math.max(total, math.max(features, entries.length)),
      installed: installed,
      verified: verified,
      issue: issue,
    );
  }

  // -------------------------------------------------------------- verify

  void toggleMappingConfirmed() => _set(state.copyWith(mappingConfirmed: !state.mappingConfirmed));

  /// The element being verified: the selection, else the Locate target.
  ArFeature? get verifyTarget {
    final f = state.primary ?? _s.target;
    return f;
  }

  double get _tolerance => _s.isLocked ? 0.35 : 0.75;

  Future<void> _checkTag(ArMarkerSighting m) async {
    final f = verifyTarget;
    final fit = _s.fit;
    if (f == null || fit == null || !fit.isPlaced || f.assetId == null) return;
    _set(state.copyWith(verify: ArVerifyCheck(assetId: f.assetId!, checking: true, toleranceM: _tolerance)));
    final tagTile = fit.arToTile(m.centreAr);
    final offset = _distanceToBox(tagTile, f);
    String? tagAsset;
    try {
      final r = m.raw == null ? null : await ref.read(c2oAssetResolverProvider).resolve(m.raw!);
      if (r is C2oResolved) tagAsset = r.assetId;
    } catch (_) {}
    if (_disposed) return;
    _set(state.copyWith(
      verify: ArVerifyCheck(
        assetId: f.assetId!,
        offsetM: offset,
        toleranceM: _tolerance,
        tagAssetId: tagAsset,
        tagMatches: tagAsset == null ? null : tagAsset == f.assetId,
      ),
    ));
  }

  /// Demo: the tag is 12 cm from the modelled box and matches the register.
  void demoScanTag() {
    final f = verifyTarget;
    if (f == null || f.assetId == null) return;
    _set(state.copyWith(
      verify: ArVerifyCheck(assetId: f.assetId!, offsetM: 0.12, toleranceM: _tolerance, tagAssetId: f.assetId, tagMatches: true),
    ));
  }

  static double _distanceToBox(Vec3 p, ArFeature f) {
    double axis(double v, double lo, double hi) => v < lo ? lo - v : (v > hi ? v - hi : 0);
    final dx = axis(p.x, math.min(f.bboxMin.x, f.bboxMax.x), math.max(f.bboxMin.x, f.bboxMax.x));
    final dy = axis(p.y, math.min(f.bboxMin.y, f.bboxMax.y), math.max(f.bboxMin.y, f.bboxMax.y));
    final dz = axis(p.z, math.min(f.bboxMin.z, f.bboxMax.z), math.max(f.bboxMin.z, f.bboxMax.z));
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  // --------------------------------------------------------------- snags

  Future<void> _loadSnagPins() async {
    final floor = _s.floor;
    if (floor == null || _s.features.isEmpty) return;
    try {
      final snags = await ref.read(snagsProvider(floor.buildingId).future);
      if (_disposed) return;
      final byAsset = <String, ArFeature>{};
      for (final f in _s.features) {
        if (f.assetId != null) byAsset[f.assetId!] = f;
      }
      final pins = <ArSnagPin>[];
      for (final Snag sn in snags) {
        if (!sn.status.isLive) continue;
        if (sn.floorId != null && sn.floorId != floor.floorId) continue;
        final f = sn.assetId == null ? null : byAsset[sn.assetId!];
        if (f != null) pins.add(ArSnagPin(snagId: sn.id, title: sn.title, feature: f));
      }
      _set(state.copyWith(snagPins: pins));
      await _session.setPins([
        for (final p in pins)
          ArPinSpec(
            id: 'snag-${p.snagId}',
            posTile: Vec3(p.feature.centre.x, p.feature.bboxMax.y + 0.2, p.feature.centre.z),
            kind: 'snag',
            label: p.title,
          ),
      ]);
    } catch (_) {
      // No local snags for this building yet: nothing to pin.
    }
  }

  // --------------------------------------------------------- feature state

  /// Rebuilds the feature-state texture with core's [FeatureState] (the
  /// encoding `packages/fe_ar`'s shader reads): the target and the
  /// selection highlighted (drawn through walls), progress tints in
  /// Progress mode or colour-by-progress, snags tinted red, and the SHOW
  /// filters (pipes, ducts, equipment, trays) hidden — one upload, no
  /// geometry change.
  ///
  /// **One texture per build, each sent with its `buildId`.** Feature ids are
  /// dense *per build* (CONTRACT C4), so with architecture and MEP on one
  /// floor id 12 names two elements; a single unscoped texture would hide or
  /// tint the other build's namesakes too (switching pipes off would hide
  /// architecture element 12). fieldops-verify, 2026-09-26: this used to
  /// style only the "active" build and send it unscoped.
  Future<void> _pushFeatureState() async {
    final s = _s;
    if (s.features.isEmpty) return;
    final byBuild = <String, List<ArFeature>>{};
    for (final f in s.features) {
      (byBuild[f.buildId] ??= <ArFeature>[]).add(f);
    }
    // Locate's x-ray context: with a target and at most one selection,
    // everything else is ghosted, in every build, so the target stands out.
    final ghostOthers = state.mode == ArMode.locate && s.target != null && state.selection.length <= 1;
    for (final entry in byBuild.entries) {
      await _pushBuildFeatureState(s, entry.key, entry.value, ghostOthers: ghostOthers);
    }
  }

  Future<void> _pushBuildFeatureState(
    ArSessionState s,
    String buildId,
    List<ArFeature> ofBuild, {
    required bool ghostOthers,
  }) async {
    var maxId = 0;
    for (final f in ofBuild) {
      maxId = math.max(maxId, f.featureId);
    }
    final colourBy = state.mode == ArMode.progress ? ArColourBy.progress : state.layers.colourBy;
    final statusByFeature = <int, String>{};
    final hidden = <int>{};
    final styles = <int, FeatureStyle>{};
    final l = state.layers;
    for (final f in ofBuild) {
      if (_filteredOut(f, l)) hidden.add(f.featureId);
      switch (colourBy) {
        case ArColourBy.progress:
          final st = state.progress.statusOf(f.globalId);
          if (st != ArProgressStatus.notStarted) statusByFeature[f.featureId] = st.wire;
        case ArColourBy.snags:
          if (state.snagPins.any((p) => p.feature.featureId == f.featureId && p.feature.buildId == f.buildId)) {
            styles[f.featureId] = const FeatureStyle(rgb: 0xEF4444);
          }
        case ArColourBy.system:
          final key = f.systemGlobalId;
          if (key != null) styles[f.featureId] = FeatureStyle(rgb: (key.hashCode & 0xFFFFFF) | 0x010101);
        case ArColourBy.discipline:
          break;
      }
    }
    final selected = state.selection.where((f) => f.buildId == buildId).map((f) => f.featureId).toSet();
    final target = <int>{if (s.target != null && s.target!.buildId == buildId) s.target!.featureId};
    final FeatureStateTexture tex;
    if (styles.isEmpty) {
      tex = FeatureState.fromStatus(
        featureCount: maxId + 1,
        statusByFeature: statusByFeature,
        selected: selected,
        target: target,
        hidden: hidden,
        ghostOthers: ghostOthers,
      );
    } else {
      for (final id in selected) {
        styles[id] = const FeatureStyle(display: FeatureDisplay.highlight, rgb: kHighlightRgb);
      }
      for (final id in target) {
        styles[id] = const FeatureStyle(display: FeatureDisplay.highlight, rgb: kHighlightRgb);
      }
      for (final id in hidden) {
        styles[id] = FeatureStyle.hidden;
      }
      tex = FeatureState.build(featureCount: maxId + 1, styles: styles);
    }
    await _session.setFeatureState(tex.rgba, tex.width, buildId: buildId);
  }

  /// The Layers panel's SHOW switches, applied per element type. They are
  /// MEP switches: architecture and structure have their own layer toggles
  /// (`setLayers`), so their elements never match here — otherwise "Equipment
  /// off" would hide every wall now that each build gets its own texture.
  /// Disciplines are the server's (`services/ar/geometry/classify.ts`).
  static bool _filteredOut(ArFeature f, ArLayerState l) {
    final d = f.discipline.toLowerCase();
    if (d.startsWith('architect') || d.startsWith('struct')) return false;
    final t = f.ifcType.toLowerCase();
    if (!l.pipes && (t.contains('pipe') || t.contains('valve'))) return true;
    if (!l.ducts && t.contains('duct')) return true;
    if (!l.cableTrays && t.contains('cable')) return true;
    if (!l.equipment && !f.isRun && !f.isValve) return true;
    return false;
  }
}

final arWorkspaceProvider = NotifierProvider.autoDispose<ArWorkspaceController, ArWorkspaceState>(
  ArWorkspaceController.new,
);
