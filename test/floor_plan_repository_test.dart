import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/data/floor_plan_repository.dart';

Map<String, dynamic> _floorJson({
  dynamic imageUrl = 'http://192.168.0.111:5002/uploads/floors/first_floor.jpg',
  List<Map<String, dynamic>>? floorAssets,
}) => {
  'id': 'floor-51',
  'floorName': 'First Floor',
  'imageUrl': imageUrl,
  'floorAssets': floorAssets ??
      [
        {
          'id': 'asset-209',
          'assetName': 'UPS Battery Backup',
          'customAttributes': {'x': 22, 'y': 68},
        },
        {
          'id': 'asset-201',
          'assetName': 'Central Air Conditioning Unit',
          // Never placed on the plan editor — no x/y at all, the normal
          // case for most assets in this dataset.
          'customAttributes': {'brand': 'Carrier'},
        },
      ],
};

void main() {
  group('FR-2.8 — FloorPlanRecord.fromJson', () {
    test('parses the plan image url and floor name', () {
      final record = FloorPlanRecord.fromJson('floor-51', _floorJson())!;
      expect(record.floorId, 'floor-51');
      expect(record.floorName, 'First Floor');
      expect(record.imageUrl, 'http://192.168.0.111:5002/uploads/floors/first_floor.jpg');
    });

    test('a seed placeholder path (not an absolute url) reads as no plan image', () {
      final record = FloorPlanRecord.fromJson('floor-51', _floorJson(imageUrl: '/images/floors/x.jpg'))!;
      expect(record.imageUrl, isNull);
    });

    test('a null imageUrl reads as no plan image, not a crash', () {
      final record = FloorPlanRecord.fromJson('floor-51', _floorJson(imageUrl: null))!;
      expect(record.imageUrl, isNull);
    });

    test('pins only the assets that actually have x/y set', () {
      final record = FloorPlanRecord.fromJson('floor-51', _floorJson())!;
      expect(record.pins, hasLength(1));
      final pin = record.pinFor('asset-209')!;
      expect(pin.xPct, 22);
      expect(pin.yPct, 68);
    });

    test('an asset with no x/y is simply not pinned, not an error', () {
      final record = FloorPlanRecord.fromJson('floor-51', _floorJson())!;
      expect(record.pinFor('asset-201'), isNull);
    });

    test('an asset id not on this floor at all is also just "not pinned"', () {
      final record = FloorPlanRecord.fromJson('floor-51', _floorJson())!;
      expect(record.pinFor('asset-does-not-exist'), isNull);
    });

    test('an empty json object returns null rather than throwing', () {
      expect(FloorPlanRecord.fromJson('floor-51', {}), isNull);
    });
  });
}
