import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ar/corner_matcher.dart' show CornerCandidate;
import 'package:technician_portal/core/ar/vec.dart';
import 'package:technician_portal/core/bim_viewer/bim_view_engine.dart';
import 'package:technician_portal/state/ar_catalog_controller.dart' show arGatewayProvider;
import 'package:technician_portal/state/ar_engine_bridge.dart' show ArTile;
import 'package:technician_portal/state/ar_view_models.dart';
import 'package:technician_portal/state/bim_viewer_controller.dart';
import 'package:technician_portal/state/bim_viewer_pack.dart';

import 'bim_viewer_fakes.dart';

/// The model viewer's controller (docs/bim-viewer.md §6) against a fake AR
/// gateway, a fake solid-wall pack and a [FakeBimViewEngine].

void main() {
  late FakeViewerGateway gateway;
  late FakeViewerPack pack;
  late ProviderContainer container;
  late FakeBimViewEngine engine;

  BimViewerController ctl() => container.read(bimViewerProvider.notifier);
  BimViewerState st() => container.read(bimViewerProvider);

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void make({bool demo = false, List<ArTile> solid = const [], List<CornerCandidate> corners = const []}) {
    gateway = FakeViewerGateway(demo: demo, corners: corners);
    pack = FakeViewerPack(gateway, tiles: solid);
    container = ProviderContainer(overrides: [
      arGatewayProvider.overrideWithValue(gateway),
      bimViewerPackProvider.overrideWithValue(pack),
    ]);
    // Keep the auto-dispose provider alive for the whole test.
    container.listen(bimViewerProvider, (_, __) {});
    engine = FakeBimViewEngine();
  }

  tearDown(() => container.dispose());

  test('open loads the floor, plan and what is on the phone', () async {
    make(solid: [tileSolid]);
    gateway.onDevice[tileMep.hash] = '/tiles/m.glb';
    await ctl().open(floorId: 'flr-3');
    final s = st();
    expect(s.loading, isFalse);
    expect(s.floor!.floorName, 'Level 3');
    expect(s.plan, isNotNull);
    expect(s.solidTiles.single.hash, tileSolid.hash);
    expect(s.localPaths.keys, [tileMep.hash]);
    expect(s.missingTiles.map((t) => t.hash), unorderedEquals([tileEdges.hash, tileSolid.hash]));
    expect(s.needsDownload, isTrue);
    expect(s.usesMassing, isTrue, reason: 'no solid tile on the phone yet');
    expect(s.bounds, [-1, -1, 21, 11]);
  });

  test('no signal and no pack: an error key, no floor', () async {
    make();
    gateway.floorError = true;
    await ctl().open(floorId: 'flr-3');
    expect(st().errorKey, 'ar.error.offline');
    expect(st().floor, isNull);
  });

  test('once the engine is up, the whole scene goes over — only local tiles', () async {
    make(solid: [tileSolid]);
    gateway.onDevice[tileMep.hash] = '/tiles/m.glb';
    gateway.onDevice[tileSolid.hash] = '/tiles/s.glb';
    ctl().attach(engine);
    await engine.start();
    await ctl().open(floorId: 'flr-3');
    await settle();

    expect(st().engineReady, isTrue);
    expect(engine.sent.map((c) => c.name).toList(),
        containsAllInOrder(['setTheme', 'setFloor', 'setPlan', 'setLayers', 'setTiles', 'setMode']));
    final tiles = engine.named('setTiles').last.args['tiles'] as List;
    expect(tiles.map((t) => (t as Map)['hash']), unorderedEquals([tileMep.hash, tileSolid.hash]));
    expect(engine.exposed, {tileMep.hash: '/tiles/m.glb', tileSolid.hash: '/tiles/s.glb'});
    // Solid walls are on the phone: plan massing stays off.
    expect(engine.named('setLayers').last.args['massing'], isFalse);
    // No corners: the datum is the wall tiles' base, plus the finish offset.
    expect(engine.named('setFloor').single.args['datumY'], closeTo(-1.55 + 0.05, 1e-9));
  });

  test('the scene is pushed once per floor, however often the engine says ready', () async {
    make();
    ctl().attach(engine);
    await engine.start();
    await ctl().open(floorId: 'flr-3');
    await settle();
    engine.emit(const BimReady(version: 1, webgl2: true));
    await settle();
    expect(engine.named('setFloor'), hasLength(1));
  });

  test('without solid tiles, "Walls" draws plan massing', () async {
    make(demo: true);
    ctl().attach(engine);
    await engine.start();
    await ctl().open(floorId: 'flr-3');
    await settle();
    expect(st().needsDownload, isFalse, reason: 'Demo never downloads');
    expect(engine.named('setLayers').last.args['massing'], isTrue);
    ctl().setLayers(st().layers.copyWith(architectureSolid: false));
    expect(engine.named('setLayers').last.args['massing'], isFalse);
  });

  test('a 3D pick names the element from the features; nothing hit clears', () async {
    make();
    ctl().attach(engine);
    await engine.start();
    await ctl().open(floorId: 'flr-3');
    await settle();
    engine.emit(const BimPick(featureId: 42, buildId: 'b1', layer: 'mep'));
    await settle();
    final sel = st().selection!;
    expect(sel.name, 'CHW pump P-01');
    expect(sel.assetId, 'asset-pump');
    expect(sel.planPolygon, isNotNull, reason: 'the pump\'s footprint lights up on the plan too');
    engine.emit(const BimPick(none: true));
    await settle();
    expect(st().selection, isNull);
  });

  test('a plan tap on equipment selects and frames it; elsewhere flies the camera', () async {
    make();
    ctl().attach(engine);
    await engine.start();
    await ctl().open(floorId: 'flr-3');
    await settle();

    ctl().tapPlan(const Vec2(4.5, 4.5), toleranceM: 0.3);
    expect(st().selection!.featureId, 42);
    final select = engine.named('select').last;
    expect(select.args['featureId'], 42);
    expect(select.args['frame'], isTrue);

    ctl().tapPlan(const Vec2(15, 8), toleranceM: 0.3);
    expect(engine.named('flyTo').last.args, {'x': 15.0, 'z': 8.0});
    expect(st().selection!.featureId, 42, reason: 'moving the camera keeps the selection');
  });

  test('opened from an asset: it is selected and framed once features load', () async {
    make();
    ctl().attach(engine);
    await engine.start();
    await ctl().open(floorId: 'flr-3', assetId: 'asset-pump', assetName: 'P-01');
    await settle();
    expect(st().selection!.assetId, 'asset-pump');
    expect(engine.named('select').last.args['frame'], isTrue);
  });

  test('pose events drive the plan dot; camera and layout changes go to the engine', () async {
    make();
    ctl().attach(engine);
    await engine.start();
    await ctl().open(floorId: 'flr-3');
    await settle();
    engine.emit(const BimPose(position: Vec3(3, 0.05, 4), direction: Vec3(0, 0, -1), mode: BimCameraMode.walk));
    await settle();
    expect(st().pose!.planPoint, const Vec2(3, 4));
    ctl().setCamera(BimCameraMode.walk);
    expect(engine.named('setMode').last.args['mode'], 'walk');
    ctl().setLayout(BimViewLayout.plan);
    expect(st().layout, BimViewLayout.plan);
  });

  test('download fetches the floor pack and the solid walls, then re-sends tiles', () async {
    make(solid: [tileSolid]);
    ctl().attach(engine);
    await engine.start();
    await ctl().open(floorId: 'flr-3');
    await settle();
    expect(st().needsDownload, isTrue);
    final before = engine.named('setTiles').length;

    await ctl().download();
    expect(gateway.downloads, 1);
    expect(pack.downloads, 1);
    expect(st().downloading, isNull);
    expect(st().needsDownload, isFalse);
    expect(st().usesMassing, isFalse);
    expect(engine.named('setTiles'), hasLength(before + 1));
    expect((engine.named('setTiles').last.args['tiles'] as List), hasLength(3));
    expect(engine.named('setLayers').last.args['massing'], isFalse);
  });

  test('a fatal engine error leaves the plan, full screen', () async {
    make();
    ctl().attach(engine);
    await engine.start();
    await ctl().open(floorId: 'flr-3');
    await settle();
    engine.emit(const BimViewerError(code: 'NO_WEBGL'));
    await settle();
    expect(st().model3dAvailable, isFalse);
    expect(st().layout, BimViewLayout.plan);
    ctl().setLayout(BimViewLayout.split);
    expect(st().layout, BimViewLayout.plan, reason: 'no 3D to split with');
  });

  group('datumFor', () {
    ArFloorContext floor({List<ArTile> tiles = const [], List<CornerCandidate> corners = const [], double datum = 0}) =>
        ArFloorContext(
          buildingId: 'b',
          buildingName: '',
          floorId: 'f',
          floorName: '',
          builds: const [],
          tiles: tiles,
          markers: const [],
          corners: corners,
          gridLines: const [],
          floorDatumY: datum,
          floorFinishOffsetM: 0.1,
        );

    test('no corners: the lowest wall base, else any tile, else 0 — plus the finish', () {
      expect(BimViewerController.datumFor(floor(tiles: [tileMep, tileEdges]), const []), closeTo(-1.45, 1e-9));
      expect(BimViewerController.datumFor(floor(tiles: [tileMep]), const []), closeTo(0.1, 1e-9));
      expect(BimViewerController.datumFor(floor(), [tileSolid]), closeTo(-1.45, 1e-9));
      expect(BimViewerController.datumFor(floor(), const []), closeTo(0.1, 1e-9));
    });
  });
}
