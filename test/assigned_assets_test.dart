import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/c2o/assigned_assets.dart';
import 'package:technician_portal/domain/maintenance_record.dart';

MaintenanceRecord _record({
  required String id,
  String? assetId,
  String? assetName,
  String? referenceId,
  String? location,
  Map<String, dynamic>? asset,
}) => MaintenanceRecord.fromJson({
  'id': id,
  'workOrderId': referenceId,
  'relatedAssetId': assetId,
  'assetName': assetName,
  'location': location,
  'asset': ?asset,
});

void main() {
  group('FR-1.6 scoping — assigned work orders as searchable assets', () {
    test('a record with no assetId is skipped', () {
      final records = [_record(id: 'wo-1', assetId: null)];
      expect(assignedAssetsFrom(records), isEmpty);
    });

    test('reads the work-order asset sub-object, which keys the name as "name" not "assetName"', () {
      final records = [
        _record(
          id: 'wo-1',
          assetId: 'asset-9',
          asset: {
            'name': 'Rooftop AHU 3',
            'manufacturer': 'Carrier',
            'model': 'X400',
            'serialNumber': 'SNAHU003',
            'supplierTagNumber': 'AST309',
            'space': 'Roof',
            'building': 'Tower B',
          },
        ),
      ];

      final assets = assignedAssetsFrom(records);
      expect(assets, hasLength(1));
      final asset = assets.single;
      expect(asset.assetId, 'asset-9');
      expect(asset.assetReferenceId, 'AST309');
      expect(asset.claims['asset']['assetName'], 'Rooftop AHU 3');
      expect(asset.claims['asset']['manufacturer'], 'Carrier');
      expect(asset.claims['asset']['serialNumber'], 'SNAHU003');
      expect(asset.claims['asset']['building'], 'Tower B');
    });

    test('falls back to the record\'s own assetName/referenceId/location when there is no asset sub-object', () {
      final records = [
        _record(
          id: 'wo-2',
          assetId: 'asset-10',
          assetName: 'Chiller Plant 1',
          referenceId: 'WO-500',
          location: 'Basement',
        ),
      ];

      final asset = assignedAssetsFrom(records).single;
      expect(asset.assetReferenceId, 'WO-500');
      expect(asset.claims['asset']['assetName'], 'Chiller Plant 1');
      expect(asset.claims['asset']['location'], 'Basement');
    });

    test('two work orders against the same asset dedupe to one entry', () {
      final records = [
        _record(id: 'wo-3', assetId: 'asset-11', assetName: 'Pump A'),
        _record(id: 'wo-4', assetId: 'asset-11', assetName: 'Pump A'),
      ];

      expect(assignedAssetsFrom(records), hasLength(1));
    });
  });
}
