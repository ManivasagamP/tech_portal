import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ar/alignment_estimator.dart';
import 'package:technician_portal/core/ar/vec.dart';
import 'package:technician_portal/domain/ar_models.dart';

const _hashA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, dynamic> _manifestJson() => {
      'buildingId': 'bld-1',
      'floorId': 'flr-3',
      'floorName': 'Level 3',
      'floorFinishOffsetM': '0.15',
      'builds': [
        {
          'buildId': 'build-mep-7',
          'lineage': 'mep-lineage',
          'modelName': 'MEP',
          'version': 7,
          'publishedAt': '2026-09-20T09:00:00.000Z',
          'coordMatrix': [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 5, 6, 0, 1],
          'buildingFrame': [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1000, 2000, 0, 1],
        },
      ],
      'tiles': [
        {
          'hash': _hashA,
          'url': '/api/bim/ar/tiles/$_hashA',
          'bytes': '1200000',
          'layer': 'mep',
          'bboxMin': ['10', 0, -2],
          'bboxMax': [18, 3, 6],
          'triangleCount': 40000,
          'buildId': 'build-mep-7',
        },
        {
          'hash': _hashB,
          'bytes': 800000,
          'layer': 'architecture',
          'bboxMin': [40, 0, 0],
          'bboxMax': [48, 3, 8],
          'triangleCount': 9000,
          'buildId': 'build-mep-7',
        },
        {'hash': 'broken-no-bbox', 'bytes': 1},
      ],
      'features': [
        {'buildId': 'build-mep-7', 'url': '/api/bim/ar/features/build-mep-7'},
      ],
      'corners': [
        {
          'id': 'c1',
          'pos': [5.75, 0, 3.75],
          'faceA': [-1, 0],
          'faceB': [0, -1],
          'angleDeg': 90,
          'kind': 'column',
          'structural': true,
          'rank': 0.95,
          'label': 'Plant Room B · column C-2',
        },
        {'id': 'c2', 'pos': [0, 0, 0]}, // no faces: skipped
      ],
      'gridLines': [
        {'name': 'A', 'p0': [0, -1], 'p1': [0, 9]},
      ],
      'markers': [
        {
          'code': '7K3QX9-R',
          'label': 'L03-M07',
          'status': 'active',
          'accuracyClass': 'feature',
          'mounting': 'wall',
          'posTile': [12.5, 1.5, -8],
          'normalTile': [-1, 0, 0],
          'sigmaM': 0.02,
        },
        {'code': '7K3QX9-M', 'posTile': [0, 0, 0], 'normalTile': [1, 0, 0]}, // bad check: skipped
      ],
      'etag': 'W/"m-17"',
    };

/// The API's four envelope shapes (envelope.dart).
List<(String, dynamic)> _envelopes(Map<String, dynamic> payload) => [
      ('{success,data}', {'success': true, 'data': payload}),
      ('{message,data}', {'message': 'ok', 'data': payload}),
      ('{data}', {'data': payload}),
      ('raw', payload),
    ];

void main() {
  group('Manifest', () {
    for (final (name, body) in _envelopes(_manifestJson())) {
      test('parses the $name envelope', () {
        final m = Manifest.fromBody(body)!;
        expect(m.floorId, 'flr-3');
        expect(m.floorName, 'Level 3');
        expect(m.floorFinishOffsetM, 0.15);
        expect(m.tiles.map((t) => t.hash), [_hashA, _hashB], reason: 'the broken tile is skipped');
        expect(m.tiles.first.bytes, 1200000);
        expect(m.tiles.first.bboxMin, const Vec3(10, 0, -2));
        expect(m.tiles[1].url, '/api/bim/ar/tiles/$_hashB', reason: 'url defaults to the tile route');
        expect(m.corners.map((c) => c.id), ['c1']);
        expect(m.markers.single.code, '7K3QX9R');
        expect(m.markers.single.codeDisplay, '7K3QX9-R');
        expect(m.gridLines.single.p1, const Vec2(0, 9));
        expect(m.builds.single.version, 7);
        expect(m.buildingFrame!.translation, const Vec3(1000, 2000, 0));
        expect(m.etag, 'W/"m-17"');
        expect(m.totalBytes, 2000000);
      });
    }

    test('focus tiles are those within 15 m of the board', () {
      final m = Manifest.fromJson(_manifestJson())!;
      expect(m.focusTiles(const Vec3(12.5, 1.5, -8)).map((t) => t.hash), [_hashA]);
      expect(m.focusTiles(null), isEmpty);
    });

    test('markerByCode accepts any code form', () {
      final m = Manifest.fromJson(_manifestJson())!;
      expect(m.markerByCode('7k3qx9-r')?.label, 'L03-M07');
      expect(m.markerByCode('4Q2MA76'), isNull);
    });

    test('an empty or non-map body is null, not a crash', () {
      expect(Manifest.fromBody(null), isNull);
      expect(Manifest.fromBody({'success': true, 'data': []}), isNull);
      expect(Manifest.fromBody({'buildingId': 'x'}), isNull, reason: 'no floorId');
    });
  });

  group('MarkerResolution', () {
    final resolveJson = {
      'marker': {
        'code': '7K3QX9R',
        'label': 'L03-M07',
        'status': 'active',
        'accuracyClass': 'feature',
        'mounting': 'wall',
        'poseTile': {
          'p': [12.41, 1.50, -8.07],
          'n': [-1, 0, 0],
        },
      },
      'building': {'id': 'bld-1', 'name': 'Tower A'},
      'floor': {'id': 'flr-3', 'name': 'Level 3'},
      'builds': [
        {'lineage': 'arch', 'buildId': 'b-arch-7', 'version': 7},
        {'lineage': 'mep', 'buildId': 'b-mep-7', 'version': '7'},
      ],
      'manifest': {
        'url': '/api/bim/ar/manifest?scope=floor&id=flr-3&focus=7K3QX9R',
        'focusBytes': 3100000,
        'totalBytes': '14000000',
      },
      'badges': ['model-older-than-upload'],
    };

    for (final (name, body) in _envelopes(resolveJson)) {
      test('parses the $name envelope (and the doc\'s poseTile {p, n} form)', () {
        final r = MarkerResolution.fromBody(body)!;
        expect(r.marker.code, '7K3QX9R');
        expect(r.marker.posTile, const Vec3(12.41, 1.5, -8.07));
        expect(r.marker.normalTile, const Vec3(-1, 0, 0));
        expect(r.building.name, 'Tower A');
        expect(r.floor.id, 'flr-3');
        expect(r.builds.map((b) => b.version), [7, 7]);
        expect(r.focusBytes, 3100000);
        expect(r.totalBytes, 14000000);
        expect(r.badges, ['model-older-than-upload']);
        expect(r.fromCache, isFalse);
      });
    }

    test('ArMarker also reads the contract\'s posTile/normalTile form', () {
      final m = ArMarker.fromJson({
        'id': 'mk-1',
        'code': '4Q2MA76',
        'label': 'SP-4Q2M',
        'status': 'spare',
        'accuracyClass': 'derived',
        'posTile': null,
        'confirmations': '2',
        'installResidualMm': '11.5',
        'lastSeenAt': '2026-09-25T10:00:00.000Z',
      })!;
      expect(m.isSpare, isTrue);
      expect(m.usableForAlignment, isFalse);
      expect(m.confirmations, 2);
      expect(m.installResidualMm, 11.5);
      expect(m.lastSeenAt, isNotNull);
      expect(ArMarker.fromJson({'code': 'nonsense'}), isNull);
    });
  });

  group('errors', () {
    test('410 RETIRED carries the nearest active board', () {
      final e = ArApiError.fromBody(410, {
        'message': 'This board was retired on 3 Sep.',
        'code': 'RETIRED',
        'nearest': {'code': 'M0R5E8-5', 'label': 'L03-M06', 'distanceM': '4.2'},
      });
      expect(e.code, ArErrorCode.retired);
      expect(e.status, 410);
      expect(e.message, 'This board was retired on 3 Sep.');
      expect(e.nearest?.code, 'M0R5E85');
      expect(e.nearest?.label, 'L03-M06');
      expect(e.nearest?.distanceM, 4.2);
    });

    test('a code inside data, or none at all (falls back by status)', () {
      expect(ArApiError.fromBody(409, {'data': {'code': 'SPARE_UNBOUND', 'message': 'Blank spare'}}).code,
          ArErrorCode.spareUnbound);
      expect(ArApiError.fromBody(404, '<html>').code, ArErrorCode.unknownCode);
      expect(ArApiError.fromBody(403, null, fallbackMessage: 'No access').message, 'No access');
    });
  });

  group('floors, features, plan, progress', () {
    test('floors list with model states and the recommended method', () {
      final floors = ArFloorSummary.listFromBody({
        'success': true,
        'data': [
          {
            'floorId': 'f1',
            'name': 'Level 1',
            'elevation': '3.6',
            'models': [
              {'lineage': 'mep', 'modelName': 'MEP', 'buildId': 'b1', 'version': 3, 'bytes': 5000, 'status': 'ready'},
              {'lineage': 'arch', 'modelName': 'Architecture', 'status': 'no-ifc', 'reason': 'Source IFC missing'},
            ],
            'markerCount': 2,
            'cornerCount': 40,
            'gridNames': ['A', 'B'],
          },
          {'floorId': 'f2', 'name': 'Level 2', 'markerCount': 0, 'cornerCount': 0, 'gridNames': ['A']},
          {'name': 'no id: skipped'},
        ],
      });
      expect(floors.map((f) => f.floorId), ['f1', 'f2']);
      expect(floors[0].readyModels.single.lineage, 'mep');
      expect(floors[0].models[1].reason, 'Source IFC missing');
      expect(floors[0].recommendedMethod, ArSetupMethod.board);
      expect(floors[1].recommendedMethod, ArSetupMethod.grid);
      expect(floors[0].readyBytes, 5000);
    });

    test('features keep their per-tile local indexes', () {
      final features = ArFeature.listFromBody([
        {
          'featureId': '12',
          'globalId': '2O2Fr\$t4X7Zf8NOew3FLOH',
          'assetId': 'asset-1',
          'discipline': 'mechanical',
          'ifcType': 'IfcPump',
          'bboxMin': [1, 0, 1],
          'bboxMax': [2, 1, 2],
          'tiles': [
            {'hash': _hashA, 'localIndex': 3},
          ],
        },
        {'featureId': 13}, // no globalId: skipped
      ], buildId: 'build-mep-7');
      expect(features.single.featureId, 12);
      expect(features.single.buildId, 'build-mep-7');
      expect(features.single.tiles.single.localIndex, 3);
      expect(features.single.centre, const Vec3(1.5, 0.5, 1.5));
    });

    test('floor plan geometry in tile XZ', () {
      final plan = FloorPlan.fromBody({
        'data': {
          'floorId': 'f1',
          'bbox': [0, 0, 12, 8],
          'walls': [
            {'id': 'w1', 'polyline': [[0, 0], [12, 0]], 'thickness': 0.3, 'structural': true},
            {'id': 'w2', 'polyline': [[0, 0]]}, // one point: skipped
          ],
          'columns': [
            {'globalId': 'col', 'polygon': [[5, 3], [6, 3], [6, 4], [5, 4]]},
          ],
          'openings': [
            {'kind': 'door', 'segment': [[2, 8], [3, 8]]},
          ],
          'spaces': [
            {'spaceId': 's1', 'name': 'Plant Room B', 'polygon': [[0, 0], [12, 0], [12, 8], [0, 8]], 'labelAt': [3, 2]},
          ],
          'equipment': [],
          'gridLines': [],
          'corners': [],
        },
      })!;
      expect(plan.bounds!.width, 12);
      expect(plan.walls.single.structural, isTrue);
      expect(plan.openings.single.b, const Vec2(3, 8));
      expect(plan.spaceAt(3, 3)?.name, 'Plant Room B');
      expect(plan.spaceAt(13, 3), isNull);
    });

    test('progress with and without a server summary', () {
      final withSummary = FloorProgress.fromBody('f1', {
        'data': {
          'statuses': [
            {'globalId': 'g1', 'status': 'installed', 'installedBy': 'u1'},
            {'globalId': 'g2', 'status': 'verified'},
          ],
          'summary': {'total': 40, 'installed': 1, 'verified': 1, 'issue': 0},
        },
      });
      expect(withSummary.summary.total, 40);
      expect(withSummary.summary.doneShare, closeTo(2 / 40, 1e-12));

      final computed = FloorProgress.fromBody('f1', {
        'statuses': [
          {'globalId': 'g1', 'status': 'installed'},
          {'globalId': 'g3', 'status': 'issue'},
        ],
      });
      expect(computed.summary.total, 2);
      expect(computed.summary.issue, 1);
    });

    test('progress update result with four-eyes rejections', () {
      final r = ProgressUpdateResult.fromBody({
        'success': true,
        'data': {
          'updated': 2,
          'rejected': [
            {'globalId': 'g9', 'reason': 'SECOND_PERSON_REQUIRED'},
          ],
        },
      });
      expect(r.updated, 2);
      expect(r.rejected.single.reason, ProgressRejectReason.secondPersonRequired);
      expect(r.queued, isFalse);
    });
  });

  group('ProgressRules — four-eyes, checked before queueing', () {
    const installedByMe = ElementProgress(globalId: 'g', status: 'installed', installedBy: 'me');

    test('the installer can\'t verify their own work', () {
      expect(ProgressRules.precheck(installedByMe, ArProgressStatus.verified, 'me'),
          ProgressRejectReason.secondPersonRequired);
    });

    test('a second person can', () {
      expect(ProgressRules.precheck(installedByMe, ArProgressStatus.verified, 'supervisor'), isNull);
    });

    test('nothing to verify before it is installed', () {
      expect(ProgressRules.precheck(null, ArProgressStatus.verified, 'x'), ProgressRejectReason.notInstalled);
      expect(
        ProgressRules.precheck(
          const ElementProgress(globalId: 'g', status: 'issue'),
          ArProgressStatus.verified,
          'x',
        ),
        ProgressRejectReason.notInstalled,
      );
    });

    test('installing and raising an issue are never blocked', () {
      expect(ProgressRules.precheck(null, ArProgressStatus.installed, 'x'), isNull);
      expect(ProgressRules.precheck(installedByMe, ArProgressStatus.issue, 'me'), isNull);
    });
  });

  test('alignment event from a fit, residuals in mm with outliers kept', () {
    final truth = Mat4.fromYawTranslation(0.3, const Vec3(1, 0, 2));
    MarkerObs obs(String id, Vec3 b, [Vec3 off = Vec3.zero]) => MarkerObs(
          id: id,
          aAr: truth.transformPoint(b) + off,
          bTile: b,
          sigmaM: 0.02,
          normalAr: truth.transformDir(const Vec3(1, 0, 0)),
          normalTile: const Vec3(1, 0, 0),
        );
    final observations = [
      obs('7K3QX9R', const Vec3(0, 1.5, 0)),
      obs('M0R5E85', const Vec3(6, 1.5, 0)),
      obs('4Q2MA76', const Vec3(6, 1.5, 5)),
      obs('0000000', const Vec3(0, 1.5, 5), const Vec3(0.3, 0, 0)),
    ];
    final fit = const AlignmentEstimator().fit(observations);
    final event = ArAlignmentEvent.fromFit(
      buildingId: 'bld',
      floorId: 'flr',
      buildIds: const ['b1'],
      fit: fit,
      observations: observations,
      distanceWalkedM: 12.4,
      deviceTier: 'A+',
      capturedAt: DateTime.utc(2026, 9, 26, 10),
    );
    final json = event.toJson();
    expect(json['quality'], 'locked');
    expect(json['method'], 'positions');
    expect((json['observations'] as List), hasLength(4));
    final outlier = (json['observations'] as List).cast<Map>().firstWhere((o) => o['ref'] == '0000000');
    expect(outlier['kind'], 'marker');
    expect(outlier['residualMm'], closeTo(300, 0.1));
    expect(json['capturedAt'], '2026-09-26T10:00:00.000Z');
  });
}
