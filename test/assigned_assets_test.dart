import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/c2o/asset_detail.dart';
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
      // FR-2's AssetDetail.fromClaims() requires claims['asset']['id'] to
      // resolve the row at all — regression coverage for the bug where an
      // assigned-only entry had every display field except this one, so
      // "View Full Details" silently landed on a not-found screen even
      // though the cache write itself succeeded.
      expect(asset.claims['asset']['id'], 'asset-9');
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

    test(
      'an assigned-only entry is something FR-2 can actually open, not a silent not-found screen',
      () {
        final records = [
          _record(id: 'wo-5', assetId: 'asset-12', assetName: 'UPS Battery Backup', location: 'First Floor'),
        ];

        final cached = assignedAssetsFrom(records).single;
        final detail = AssetDetail.fromClaims(cached.claims);

        expect(detail, isNotNull);
        expect(detail!.id, 'asset-12');
        expect(detail.assetName, 'UPS Battery Backup');
      },
    );

    test(
      'the reference id is duplicated into claims too, not just the outer cache row — '
      'real seed data with no assetName anywhere needs it as FR-2\'s identity-block fallback',
      () {
        final records = [
          _record(id: 'wo-6', assetId: 'asset-13', referenceId: 'WO-757'),
        ];

        final cached = assignedAssetsFrom(records).single;
        expect(cached.assetReferenceId, 'WO-757');
        expect(cached.claims['asset']['assetReferenceId'], 'WO-757');

        final detail = AssetDetail.fromClaims(cached.claims)!;
        expect(detail.assetName, isNull);
        expect(detail.assetReferenceId, 'WO-757');
      },
    );
  });
}
