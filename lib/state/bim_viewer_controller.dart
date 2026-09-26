import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ar/vec.dart';
import '../core/bim_viewer/bim_view_engine.dart';
import '../core/bim_viewer/plan_view_math.dart';
import 'ar_catalog_controller.dart' show arGatewayProvider;
import 'ar_engine_bridge.dart' show ArTile;
import 'ar_gateway.dart';
import 'ar_session_controller.dart' show arErrorKey;
import 'ar_view_models.dart';
import 'bim_viewer_pack.dart';

/// The 2D/3D model viewer (docs/bim-viewer.md): Dalux-style split view of
/// the floor's model (3D, orbit or walk) over its plan (2D), with a
/// position dot and view cone on the plan that follow the 3D camera, and a
/// tap on the plan that moves the camera there.
///
/// Data comes from the AR floor pack ([ArGateway]) plus the viewer-only
/// solid-wall tiles ([BimViewerPack]); nothing here talks to the network
/// directly, so it works offline on a downloaded floor and in Demo mode.
/// The 3D engine is a [BimViewEngine] the screen creates and [attach]es.

enum BimViewLayout { split, model, plan }

/// What is selected: a model element (from a 3D pick or a plan tap on
/// equipment) or a plan equipment footprint with no model element behind it.
class BimSelection {
  const BimSelection({
    required this.name,
    this.featureId,
    this.buildId,
    this.globalId,
    this.assetId,
    this.ifcType,
    this.discipline,
    this.bboxMin,
    this.bboxMax,
    this.planPolygon,
  });

  final String name;
  final int? featureId;
  final String? buildId;
  final String? globalId;
  final String? assetId;
  final String? ifcType;
  final String? discipline;
  final Vec3? bboxMin;
  final Vec3? bboxMax;

  /// Its footprint on the plan (equipment), for the 2D highlight.
  final List<Vec2>? planPolygon;

  /// Where it sits on the plan.
  Vec2? get planPoint {
    final min = bboxMin, max = bboxMax;
    if (min != null && max != null) return Vec2((min.x + max.x) / 2, (min.z + max.z) / 2);
    final poly = planPolygon;
    if (poly == null || poly.isEmpty) return null;
    var x = 0.0, z = 0.0;
    for (final p in poly) {
      x += p.x;
      z += p.y;
    }
    return Vec2(x / poly.length, z / poly.length);
  }

  factory BimSelection.ofFeature(ArFeature f, {List<Vec2>? planPolygon}) => BimSelection(
        name: f.displayName,
        featureId: f.featureId,
        buildId: f.buildId,
        globalId: f.globalId,
        assetId: f.assetId,
        ifcType: f.ifcType,
        discipline: f.discipline,
        bboxMin: f.bboxMin,
        bboxMax: f.bboxMax,
        planPolygon: planPolygon,
      );
}

const _keep = Object();

class BimViewerState {
  const BimViewerState({
    this.floorId,
    this.focusAssetId,
    this.focusAssetName,
    this.loading = false,
    this.errorKey,
    this.isDemo = false,
    this.floor,
    this.plan,
    this.arTiles = const [],
    this.solidTiles = const [],
    this.localPaths = const {},
    this.downloading,
    this.downloadErrorKey,
    this.layout = BimViewLayout.split,
    this.camera = BimCameraMode.orbit,
    this.layers = const BimLayerState(),
    this.pose,
    this.selection,
    this.engineReady = false,
    this.engineErrorCode,
    this.tilesLoaded = 0,
    this.tilesTotal = 0,
    this.tilesDone = false,
    this.dark = false,
  });

  final String? floorId;
  final String? focusAssetId;
  final String? focusAssetName;
  final bool loading;
  final String? errorKey;
  final bool isDemo;
  final ArFloorContext? floor;
  final ArPlan? plan;

  /// The AR floor pack's tiles (MEP, structure, architecture edges).
  final List<ArTile> arTiles;

  /// The viewer-only `architecture_solid` tiles.
  final List<ArTile> solidTiles;

  /// Tiles on this phone: hash → file.
  final Map<String, String> localPaths;
  final ArDownloadProgress? downloading;
  final String? downloadErrorKey;
  final BimViewLayout layout;
  final BimCameraMode camera;
  final BimLayerState layers;
  final BimPose? pose;
  final BimSelection? selection;
  final bool engineReady;

  /// A fatal engine error (no WebGL…): the 3D half is off, the plan stays.
  final String? engineErrorCode;
  final int tilesLoaded;
  final int tilesTotal;
  final bool tilesDone;
  final bool dark;

  List<ArTile> get allTiles => [...arTiles, ...solidTiles];
  List<ArTile> get missingTiles => [for (final t in allTiles) if (!localPaths.containsKey(t.hash)) t];
  int get missingBytes => missingTiles.fold(0, (s, t) => s + t.bytes);
  bool get needsDownload => !isDemo && missingTiles.isNotEmpty;
  bool get model3dAvailable => engineErrorCode == null;

  /// No shaded wall tiles on the phone: walls are extruded from the plan.
  bool get usesMassing => !solidTiles.any((t) => localPaths.containsKey(t.hash));

  bool get fromCache => floor?.fromCache ?? false;

  /// The floor's datum in the tile frame, plus the finished-floor offset.
  double get datumY => floor == null ? 0 : BimViewerController.datumFor(floor!, solidTiles);

  /// `[minX, minZ, maxX, maxZ]` for framing: the plan, else the tiles.
  List<double> get bounds {
    final p = plan;
    if (p != null) return [p.minX, p.minZ, p.maxX, p.maxZ];
    final pts = [
      for (final t in allTiles) ...[t.bboxMin.xz, t.bboxMax.xz],
    ];
    return boundsOf(pts, marginM: 1) ?? const [-10, -10, 10, 10];
  }

  BimViewerState copyWith({
    Object? floorId = _keep,
    Object? focusAssetId = _keep,
    Object? focusAssetName = _keep,
    bool? loading,
    Object? errorKey = _keep,
    bool? isDemo,
    Object? floor = _keep,
    Object? plan = _keep,
    List<ArTile>? arTiles,
    List<ArTile>? solidTiles,
    Map<String, String>? localPaths,
    Object? downloading = _keep,
    Object? downloadErrorKey = _keep,
    BimViewLayout? layout,
    BimCameraMode? camera,
    BimLayerState? layers,
    Object? pose = _keep,
    Object? selection = _keep,
    bool? engineReady,
    Object? engineErrorCode = _keep,
    int? tilesLoaded,
    int? tilesTotal,
    bool? tilesDone,
    bool? dark,
  }) =>
      BimViewerState(
        floorId: floorId == _keep ? this.floorId : floorId as String?,
        focusAssetId: focusAssetId == _keep ? this.focusAssetId : focusAssetId as String?,
        focusAssetName: focusAssetName == _keep ? this.focusAssetName : focusAssetName as String?,
        loading: loading ?? this.loading,
        errorKey: errorKey == _keep ? this.errorKey : errorKey as String?,
        isDemo: isDemo ?? this.isDemo,
        floor: floor == _keep ? this.floor : floor as ArFloorContext?,
        plan: plan == _keep ? this.plan : plan as ArPlan?,
        arTiles: arTiles ?? this.arTiles,
        solidTiles: solidTiles ?? this.solidTiles,
        localPaths: localPaths ?? this.localPaths,
        downloading: downloading == _keep ? this.downloading : downloading as ArDownloadProgress?,
        downloadErrorKey: downloadErrorKey == _keep ? this.downloadErrorKey : downloadErrorKey as String?,
        layout: layout ?? this.layout,
        camera: camera ?? this.camera,
        layers: layers ?? this.layers,
        pose: pose == _keep ? this.pose : pose as BimPose?,
        selection: selection == _keep ? this.selection : selection as BimSelection?,
        engineReady: engineReady ?? this.engineReady,
        engineErrorCode: engineErrorCode == _keep ? this.engineErrorCode : engineErrorCode as String?,
        tilesLoaded: tilesLoaded ?? this.tilesLoaded,
        tilesTotal: tilesTotal ?? this.tilesTotal,
        tilesDone: tilesDone ?? this.tilesDone,
        dark: dark ?? this.dark,
      );
}

class BimViewerController extends AutoDisposeNotifier<BimViewerState> {
  BimViewEngine? _engine;
  StreamSubscription<BimViewEvent>? _events;
  var _disposed = false;
  var _openToken = 0;
  String? _scenePushedFor;
  List<ArFeature> _features = const [];

  @override
  BimViewerState build() {
    ref.onDispose(() {
      _disposed = true;
      unawaited(_events?.cancel());
    });
    return const BimViewerState();
  }

  void _set(BimViewerState s) {
    if (!_disposed) state = s;
  }

  ArGateway get _gateway => ref.read(arGatewayProvider);
  BimViewerPack get _pack => ref.read(bimViewerPackProvider);

  // ------------------------------------------------------------------ open

  /// Loads a floor: the AR floor pack (offline from the phone), its plan,
  /// the solid-wall tiles, what's on the phone. [assetId] (from the asset
  /// screen) is selected and framed once the features are known.
  Future<void> open({required String floorId, String? assetId, String? assetName}) async {
    final token = ++_openToken;
    _scenePushedFor = null;
    _features = const [];
    final gateway = _gateway;
    _set(BimViewerState(
      floorId: floorId,
      focusAssetId: assetId,
      focusAssetName: assetName,
      loading: true,
      isDemo: gateway.isDemo,
      layout: state.layout,
      camera: state.camera,
      layers: state.layers,
      dark: state.dark,
      engineReady: state.engineReady,
      engineErrorCode: state.engineErrorCode,
    ));

    final ArFloorContext floor;
    try {
      floor = await gateway.floorContext(floorId);
    } catch (e) {
      if (token != _openToken) return;
      _set(state.copyWith(loading: false, errorKey: arErrorKey(e)));
      return;
    }
    if (token != _openToken) return;

    final results = await Future.wait<Object?>([
      gateway.floorPlan(floorId).then<Object?>((p) => p, onError: (_) => null),
      (gateway.isDemo ? Future.value(const <ArTile>[]) : _pack.solidTiles(floorId))
          .then<Object?>((t) => t, onError: (_) => const <ArTile>[]),
    ]);
    if (token != _openToken) return;
    final plan = results[0] as ArPlan?;
    final solid = results[1] as List<ArTile>;
    final paths = await _localPaths([...floor.tiles, ...solid]);
    if (token != _openToken) return;

    _set(state.copyWith(
      loading: false,
      floor: floor,
      plan: plan,
      arTiles: floor.tiles,
      solidTiles: solid,
      localPaths: paths,
    ));
    _pushScene();
    unawaited(_loadFeatures(floor, token));
  }

  Future<Map<String, String>> _localPaths(List<ArTile> tiles) async {
    if (tiles.isEmpty) return const {};
    try {
      return await _gateway.tilePaths(tiles);
    } catch (_) {
      return const {};
    }
  }

  Future<void> _loadFeatures(ArFloorContext floor, int token) async {
    try {
      final f = await _gateway.features(floor);
      if (token != _openToken || _disposed) return;
      _features = f;
    } catch (_) {
      return; // picks still highlight; they just can't name the element
    }
    _focusRequestedAsset();
  }

  void _focusRequestedAsset() {
    final assetId = state.focusAssetId;
    if (assetId == null || state.selection != null) return;
    final feature = _features.where((f) => f.assetId == assetId).firstOrNull;
    final equipment = state.plan?.equipment.where((e) => e.assetId == assetId).firstOrNull;
    if (feature != null) {
      _select(BimSelection.ofFeature(feature, planPolygon: equipment?.polygon), frame: true);
    } else if (equipment != null) {
      _select(
        BimSelection(name: state.focusAssetName ?? equipment.name, assetId: assetId, globalId: equipment.globalId, planPolygon: equipment.polygon),
        frame: true,
      );
    }
  }

  // --------------------------------------------------------------- download

  /// Downloads the floor pack (shared with AR) and the solid-wall tiles.
  Future<void> download() async {
    final floor = state.floor;
    final floorId = state.floorId;
    if (floor == null || floorId == null || state.downloading != null || state.isDemo) return;
    final arMissing = floor.tiles.where((t) => !state.localPaths.containsKey(t.hash)).fold<int>(0, (s, t) => s + t.bytes);
    final solidMissing =
        state.solidTiles.where((t) => !state.localPaths.containsKey(t.hash)).fold<int>(0, (s, t) => s + t.bytes);
    final total = math.max(1, arMissing + solidMissing);
    _set(state.copyWith(downloading: ArDownloadProgress(totalBytes: total), downloadErrorKey: null));
    try {
      if (arMissing > 0) {
        await _gateway.download(floor, onProgress: (p) {
          final done = (arMissing * p.fraction).round();
          _set(state.copyWith(downloading: ArDownloadProgress(doneBytes: done, totalBytes: total)));
        });
      }
      if (solidMissing > 0) {
        await _pack.download(floorId, onProgress: (p) {
          final done = arMissing + (solidMissing * p.fraction).round();
          _set(state.copyWith(downloading: ArDownloadProgress(doneBytes: done, totalBytes: total)));
        });
      }
      _set(state.copyWith(downloading: null));
    } catch (e) {
      _set(state.copyWith(downloading: null, downloadErrorKey: arErrorKey(e)));
    }
    // Whatever arrived is usable, complete or not.
    final paths = await _localPaths(state.allTiles);
    _set(state.copyWith(localPaths: paths));
    _pushTiles();
    _pushLayers();
  }

  // ----------------------------------------------------------------- engine

  /// The screen created an engine: listen, and push the scene once it's up.
  void attach(BimViewEngine engine) {
    if (identical(engine, _engine)) return;
    unawaited(_events?.cancel());
    _engine = engine;
    _scenePushedFor = null;
    _set(state.copyWith(engineReady: false, engineErrorCode: null));
    _events = engine.events.listen(_onEvent, onError: (_) {});
  }

  /// The screen is going (called from its `dispose`): stop listening. No
  /// state change here — the tree is being torn down, and this auto-dispose
  /// provider goes with it; a later [attach] resets `engineReady` anyway.
  void detach() {
    unawaited(_events?.cancel());
    _events = null;
    _engine = null;
    _scenePushedFor = null;
  }

  void _onEvent(BimViewEvent e) {
    switch (e) {
      case BimReady():
        _set(state.copyWith(engineReady: true, engineErrorCode: null));
        _pushScene();
      case BimPose():
        _set(state.copyWith(pose: e));
      case BimPick():
        _onPick(e);
      case BimTilesProgress():
        _set(state.copyWith(tilesLoaded: e.loaded, tilesTotal: e.total, tilesDone: e.done));
      case BimViewerError():
        if (e.fatal) {
          // No 3D on this phone: keep the plan, full screen.
          _set(state.copyWith(engineErrorCode: e.code, layout: BimViewLayout.plan));
        }
    }
  }

  void _send(BimViewCommand c) {
    final e = _engine;
    if (e != null && state.engineReady) unawaited(e.send(c));
  }

  /// Everything the engine needs for this floor, once per floor per engine.
  void _pushScene() {
    final e = _engine;
    final floor = state.floor;
    if (e == null || !state.engineReady || floor == null) return;
    if (_scenePushedFor == floor.floorId) return;
    _scenePushedFor = floor.floorId;
    _send(BimViewCommand.setTheme(dark: state.dark));
    _send(BimViewCommand.setFloor(datumY: state.datumY, bounds: state.bounds));
    final plan = state.plan;
    if (plan != null) {
      _send(BimViewCommand.setPlan(
        datumY: state.datumY,
        bounds: state.bounds,
        walls: [for (final w in plan.walls) BimMassingWall(w)],
        columns: plan.columns,
      ));
    }
    _pushLayers();
    _pushTiles();
    _send(BimViewCommand.setMode(state.camera));
    final sel = state.selection;
    if (sel != null) _selectInEngine(sel, frame: true);
  }

  void _pushTiles() {
    final e = _engine;
    if (e == null || !state.engineReady) return;
    final local = [for (final t in state.allTiles) if (state.localPaths.containsKey(t.hash)) t];
    final base = e.exposeTiles({for (final t in local) t.hash: state.localPaths[t.hash]!});
    _send(BimViewCommand.setTiles(
      base: base,
      tiles: [for (final t in local) BimTileSpec(hash: t.hash, layer: t.layer, buildId: t.buildId)],
    ));
  }

  /// The user's toggles, with "Walls" meaning shaded tiles when the phone
  /// has them and plan-extruded walls when it doesn't.
  BimLayerState get effectiveLayers {
    final l = state.layers;
    return l.copyWith(massing: l.architectureSolid && state.usesMassing);
  }

  void _pushLayers() => _send(BimViewCommand.setLayers(effectiveLayers));

  // ----------------------------------------------------------------- inputs

  void setDark(bool dark) {
    if (dark == state.dark) return;
    _set(state.copyWith(dark: dark));
    _send(BimViewCommand.setTheme(dark: dark));
  }

  void setLayout(BimViewLayout layout) {
    if (!state.model3dAvailable && layout != BimViewLayout.plan) return;
    _set(state.copyWith(layout: layout));
  }

  void setCamera(BimCameraMode mode) {
    if (mode == state.camera) return;
    _set(state.copyWith(camera: mode));
    _send(BimViewCommand.setMode(mode));
  }

  void setLayers(BimLayerState layers) {
    _set(state.copyWith(layers: layers));
    _pushLayers();
  }

  void resetView() => _send(BimViewCommand.resetView());

  void clearSelection() {
    _set(state.copyWith(selection: null));
    _send(BimViewCommand.clearSelection());
  }

  /// A tap on the plan at [p] (metres). Equipment under the finger is
  /// selected and framed in 3D; anywhere else moves the 3D camera there.
  void tapPlan(Vec2 p, {required double toleranceM}) {
    final plan = state.plan;
    if (plan != null && plan.equipment.isNotEmpty) {
      final i = hitPolygon([for (final e in plan.equipment) e.polygon], p, toleranceM);
      if (i != null) {
        final eq = plan.equipment[i];
        final feature = eq.globalId == null ? null : _features.where((f) => f.globalId == eq.globalId).firstOrNull;
        _select(
          feature != null
              ? BimSelection.ofFeature(feature, planPolygon: eq.polygon)
              : BimSelection(name: eq.name, globalId: eq.globalId, assetId: eq.assetId, planPolygon: eq.polygon),
          frame: true,
        );
        return;
      }
    }
    _send(BimViewCommand.flyTo(x: p.x, z: p.y));
  }

  void _onPick(BimPick e) {
    final id = e.featureId;
    if (id == null) {
      _set(state.copyWith(selection: null));
      return;
    }
    final feature = _features
        .where((f) => f.featureId == id && (e.buildId == null || f.buildId == e.buildId))
        .firstOrNull;
    if (feature == null) {
      // Features not loaded (offline, first open): still say what was hit.
      _set(state.copyWith(selection: BimSelection(name: '#$id', featureId: id, buildId: e.buildId)));
      return;
    }
    final eq = state.plan?.equipment.where((q) => q.globalId == feature.globalId).firstOrNull;
    // The page already highlighted it; no need to send `select` back.
    _set(state.copyWith(selection: BimSelection.ofFeature(feature, planPolygon: eq?.polygon)));
  }

  void _select(BimSelection sel, {required bool frame}) {
    _set(state.copyWith(selection: sel));
    _selectInEngine(sel, frame: frame);
  }

  void _selectInEngine(BimSelection sel, {required bool frame}) {
    final id = sel.featureId;
    if (id != null) {
      _send(BimViewCommand.select(featureId: id, buildId: sel.buildId, frame: frame, bboxMin: sel.bboxMin, bboxMax: sel.bboxMax));
      return;
    }
    final p = sel.planPoint;
    if (p != null && frame) _send(BimViewCommand.flyTo(x: p.x, z: p.y));
  }

  // ------------------------------------------------------------------ pure

  /// The floor's datum (tile-frame y of the floor) for eye height, the
  /// section cut and plan massing: the corner candidates sit on the floor;
  /// without corners, the lowest base of the walls (architecture tiles);
  /// without those, any tile. Plus the finished-floor offset (AR-45).
  static double datumFor(ArFloorContext floor, List<ArTile> solidTiles) {
    double base;
    if (floor.corners.isNotEmpty) {
      base = floor.floorDatumY;
    } else {
      final all = [...floor.tiles, ...solidTiles];
      final walls = all.where((t) => t.layer == 'architecture' || t.layer == 'architecture_solid');
      final pick = walls.isNotEmpty ? walls : all;
      base = pick.isEmpty ? 0 : pick.map((t) => t.bboxMin.y).reduce(math.min);
    }
    return base + floor.floorFinishOffsetM;
  }
}

final bimViewerProvider = NotifierProvider.autoDispose<BimViewerController, BimViewerState>(
  BimViewerController.new,
);
