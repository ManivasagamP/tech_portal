import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ar/vec.dart';
import 'package:technician_portal/core/bim_viewer/bim_view_wire.dart';

/// The Dart ↔ viewer.js wire (docs/bim-viewer.md §4). viewer.js is checked
/// against the same shapes by tool/bim_viewer/e2e.mjs in a real browser.
void main() {
  group('commands', () {
    test('every command is {cmd, args} with viewer.js names', () {
      expect(BimViewCommand.setTheme(dark: true).toJson(), {'cmd': 'setTheme', 'args': {'dark': true}});
      expect(BimViewCommand.setMode(BimCameraMode.walk).toJson(), {'cmd': 'setMode', 'args': {'mode': 'walk'}});
      expect(BimViewCommand.resetView().toJson(), {'cmd': 'resetView', 'args': <String, Object?>{}});
      expect(BimViewCommand.clearSelection().name, 'clearSelection');
      final floor = BimViewCommand.setFloor(datumY: -1.55, bounds: [0, 0, 20, 10]).args;
      expect(floor, {'datumY': -1.55, 'bounds': [0, 0, 20, 10], 'eyeHeightM': 1.6, 'cutHeightM': 2.2});
    });

    test('layers use the server\'s tile layer names', () {
      const l = BimLayerState(architectureSolid: false, xray: true);
      expect(BimViewCommand.setLayers(l).args, {
        'mep': true,
        'structure': true,
        'architecture': true,
        'architecture_solid': false,
        'massing': true,
        'xray': true,
        'cut': true,
      });
      expect(l.copyWith(xray: false), const BimLayerState(architectureSolid: false));
    });

    test('setTiles lists hash, layer and build', () {
      final c = BimViewCommand.setTiles(
        base: 'http://127.0.0.1:1/t/tiles/',
        tiles: const [BimTileSpec(hash: 'ab', layer: 'architecture_solid', buildId: 'b1')],
      );
      expect(c.args['base'], 'http://127.0.0.1:1/t/tiles/');
      expect(c.args['tiles'], [
        {'hash': 'ab', 'layer': 'architecture_solid', 'buildId': 'b1'},
      ]);
    });

    test('setPlan rounds to millimetres and keeps wall thickness', () {
      final c = BimViewCommand.setPlan(
        datumY: 0,
        walls: const [BimMassingWall([Vec2(0.00012, 1), Vec2(4.12345, 1)], thicknessM: 0.3)],
        columns: const [
          [Vec2(1, 1), Vec2(1.5, 1), Vec2(1.5, 1.5)],
        ],
      );
      expect(c.args['walls'], [
        {
          'pts': [
            [0.0, 1.0],
            [4.123, 1.0],
          ],
          't': 0.3,
        },
      ]);
      expect((c.args['columns'] as List).single, hasLength(3));
    });

    test('select and flyTo carry only what was given', () {
      expect(BimViewCommand.select(featureId: 7).args, {'featureId': 7, 'buildId': null, 'frame': true});
      final withBox = BimViewCommand.select(featureId: 7, buildId: 'b', bboxMin: const Vec3(0, 1, 2), bboxMax: const Vec3(3, 4, 5));
      expect(withBox.args['bboxMin'], [0.0, 1.0, 2.0]);
      expect(BimViewCommand.flyTo(x: 1, z: 2).args, {'x': 1.0, 'z': 2.0});
      expect(BimViewCommand.flyTo(x: 1, z: 2, heading: const Vec2(0, -1)).args, {'x': 1.0, 'z': 2.0, 'headingX': 0.0, 'headingZ': -1.0});
    });

    test('toJavaScript is one call with escaped JSON — a model name cannot break out', () {
      final js = BimViewCommand.setTiles(
        base: "x'); alert(1); ('",
        tiles: const [BimTileSpec(hash: 'h', layer: 'mep', buildId: '"</script>')],
      ).toJavaScript();
      expect(js, startsWith('window.feViewer.run('));
      expect(js, endsWith(');'));
      final inner = js.substring('window.feViewer.run('.length, js.length - 2);
      expect((jsonDecode(inner) as Map)['cmd'], 'setTiles');
    });
  });

  group('events', () {
    test('ready, tiles, error', () {
      final r = BimViewEvent.parse('{"type":"ready","version":1,"webgl2":true}');
      expect(r, isA<BimReady>().having((e) => e.webgl2, 'webgl2', isTrue));
      final t = BimViewEvent.parse({'type': 'tiles', 'loaded': 60, 'failed': 0, 'total': 60, 'resident': 60, 'triangles': 127410, 'done': true});
      expect(t, isA<BimTilesProgress>().having((e) => e.done, 'done', isTrue).having((e) => e.triangles, 'tri', 127410));
      final e = BimViewEvent.parse({'type': 'error', 'code': 'NO_WEBGL', 'message': 'x'}) as BimViewerError;
      expect(e.fatal, isTrue);
      expect((BimViewEvent.parse({'type': 'error', 'code': 'UNKNOWN_COMMAND'}) as BimViewerError).fatal, isFalse);
    });

    test('pose: plan point is the walker, or the orbited target', () {
      final walk = BimViewEvent.parse({'type': 'pose', 'pos': [2, 1.6, 3], 'dir': [0, 0, -1], 'mode': 'walk', 'fovDeg': 60}) as BimPose;
      expect(walk.mode, BimCameraMode.walk);
      expect(walk.planPoint, const Vec2(2, 3));
      expect(walk.planHeading, const Vec2(0, -1));
      final orbit = BimViewEvent.parse({
        'type': 'pose',
        'pos': [20, 30, 20],
        'dir': [-0.5, -0.7, -0.5],
        'mode': 'orbit',
        'target': [5, 0, 6],
      }) as BimPose;
      expect(orbit.planPoint, const Vec2(5, 6));
      final down = BimViewEvent.parse({'type': 'pose', 'pos': [0, 9, 0], 'dir': [0, -1, 0], 'mode': 'orbit'}) as BimPose;
      expect(down.planHeading, isNull);
      expect(down.planPoint, const Vec2(0, 0), reason: 'no target: the camera\'s own point');
    });

    test('pick: a feature, or nothing', () {
      final p = BimViewEvent.parse({'type': 'pick', 'featureId': 142, 'buildId': 'b', 'layer': 'architecture_solid', 'point': [1, 2, 3]}) as BimPick;
      expect(p.featureId, 142);
      expect(p.point, const Vec3(1, 2, 3));
      final none = BimViewEvent.parse({'type': 'pick', 'none': true}) as BimPick;
      expect(none.none, isTrue);
      expect(none.featureId, isNull);
      final floor = BimViewEvent.parse({'type': 'pick', 'featureId': null, 'point': [0, 0, 0], 'layer': 'floor'}) as BimPick;
      expect(floor.featureId, isNull);
    });

    test('unknown or malformed messages are ignored, never thrown', () {
      expect(BimViewEvent.parse('{"type":"future-thing"}'), isNull);
      expect(BimViewEvent.parse('not json'), isNull);
      expect(BimViewEvent.parse(42), isNull);
      expect(BimViewEvent.parse({'type': 'pose', 'pos': [1, 2]}), isNull);
      expect((BimViewEvent.parse({'type': 'pick', 'featureId': 1.5}) as BimPick).featureId, isNull);
    });
  });
}
