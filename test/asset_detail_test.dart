import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/c2o/asset_detail.dart';

Map<String, dynamic> _claims({
  Map<String, dynamic>? assetOverrides,
  List<Map<String, dynamic>>? history,
  List<Map<String, dynamic>>? openFindings,
}) => {
  'asset': {
    'id': 'asset-9',
    'assetReferenceId': 'AST309',
    'assetName': 'Rooftop AHU 3',
    'type': 'HVAC Equipment',
    'category': 'Air Handling',
    'imageUrl': 'https://example.com/ahu.jpg',
    'locationPath': [
      {'level': 'Building', 'label': 'Tower B', 'code': 'B'},
      {'level': 'Level', 'label': null, 'code': 'L02'},
    ],
    'manufacturer': 'Carrier',
    'model': 'X400',
    'serialNumber': 'SNAHU003',
    'supplierTagNumber': 'AST309',
    'barcode': 'QR-AST309',
    'warrantyExpiryDate': '2025-06-12T00:00:00.000Z',
    'systemCode': 'ACS',
    'isMaintainable': true,
    'physicalTagStatus': 'tag-expected',
    'condition': 'good',
    'floorID': 'floor-2',
    ...?assetOverrides,
  },
  'history': history ??
      [
        {
          'id': 'h1',
          'result': 'verified',
          'verifiedAt': '2026-06-01T10:00:00.000Z',
          'verifiedByName': 'Balaji',
          'discrepancies': [],
        },
      ],
  'openFindings': openFindings ?? const [],
};

void main() {
  group('FR-2 data shaping — AssetDetail.fromClaims', () {
    test('parses the identity block', () {
      final detail = AssetDetail.fromClaims(_claims())!;
      expect(detail.id, 'asset-9');
      expect(detail.assetReferenceId, 'AST309');
      expect(detail.assetName, 'Rooftop AHU 3');
      expect(detail.type, 'HVAC Equipment');
      expect(detail.imageUrl, 'https://example.com/ahu.jpg');
    });

    test('parses the location walk, keeping name and code separate', () {
      final detail = AssetDetail.fromClaims(_claims())!;
      expect(detail.locationPath, hasLength(2));
      expect(detail.locationPath[0].level, 'Building');
      expect(detail.locationPath[0].label, 'Tower B');
      expect(detail.locationPath[0].code, 'B');
      // A rung with no name still keeps its code rather than dropping it.
      expect(detail.locationPath[1].label, isNull);
      expect(detail.locationPath[1].code, 'L02');
    });

    test('parses nameplate claims', () {
      final detail = AssetDetail.fromClaims(_claims())!;
      expect(detail.manufacturer, 'Carrier');
      expect(detail.model, 'X400');
      expect(detail.serialNumber, 'SNAHU003');
      expect(detail.supplierTagNumber, 'AST309');
      expect(detail.barcode, 'QR-AST309');
    });

    test('parses status chip fields', () {
      final detail = AssetDetail.fromClaims(_claims())!;
      expect(detail.systemCode, 'ACS');
      expect(detail.isMaintainable, true);
      expect(detail.physicalTagStatus, 'tag-expected');
      expect(detail.condition, 'good');
    });

    test('the last check is the first (newest) history row', () {
      final detail = AssetDetail.fromClaims(_claims())!;
      expect(detail.lastCheck, isNotNull);
      expect(detail.lastCheck!.result, 'verified');
      expect(detail.lastCheck!.verifiedByName, 'Balaji');
    });

    test('an empty history list means no last check, not a crash', () {
      final detail = AssetDetail.fromClaims(_claims(history: []))!;
      expect(detail.lastCheck, isNull);
    });

    test('parses open findings (FR-2.7)', () {
      final detail = AssetDetail.fromClaims(_claims(openFindings: [
        {
          'id': 'f1',
          'severity': 'blocker',
          'message': 'Asset AST309 could not be found at its registered location.',
          'fixHint': 'Confirm whether it was ever installed.',
          'ruleName': 'Field verification mismatch',
          'createdAt': '2026-08-01T00:00:00.000Z',
        },
      ]))!;
      expect(detail.openFindings, hasLength(1));
      final f = detail.openFindings.single;
      expect(f.severity, 'blocker');
      expect(f.message, contains('could not be found'));
      expect(f.ruleName, 'Field verification mismatch');
    });

    test('no findings means an empty list, not null or a crash', () {
      final detail = AssetDetail.fromClaims(_claims())!;
      expect(detail.openFindings, isEmpty);
    });

    test('parses the floor id (FR-2.8)', () {
      final detail = AssetDetail.fromClaims(_claims())!;
      expect(detail.floorId, 'floor-2');
    });

    test('no floor on the register means no floor id, not a crash', () {
      final detail = AssetDetail.fromClaims(_claims(assetOverrides: {'floorID': null}))!;
      expect(detail.floorId, isNull);
    });

    test('a missing asset object returns null rather than throwing', () {
      expect(AssetDetail.fromClaims({'history': []}), isNull);
    });

    test('a location rung with neither label nor code still parses (server already drops those)', () {
      final detail = AssetDetail.fromClaims(
        _claims(assetOverrides: {
          'locationPath': [
            {'level': 'Position', 'label': null, 'code': null},
          ],
        }),
      )!;
      expect(detail.locationPath.single.label, isNull);
      expect(detail.locationPath.single.code, isNull);
    });
  });

  group('FR-2 fallback — AssetDetail.fromAssetRecord (full GET /api/fm/assets/:id)', () {
    Map<String, dynamic> record({Map<String, dynamic>? overrides}) => {
      'id': 'asset-77',
      'assetReferenceId': 'AST009',
      'assetName': 'UPS Battery Backup',
      'type': 'Electrical Equipment',
      'category': 'Power Distribution',
      'location': 'Fusion Eco Tower A - First Floor - Open Workspace A',
      'manufacturer': 'APC',
      'model': 'Smart-UPS 3000VA',
      'serialNumber': 'APC-UPS-001-2022',
      'qrCode': 'QR-UPS-001',
      'warrantyExpiryDate': '2025-02-28T00:00:00.000Z',
      'condition': 'good',
      'maintainability': 'maintainable',
      'description': 'Uninterruptible power supply for critical equipment',
      'imageUrl': '/images/assets/ups-001.jpg',
      'floorID': 'floor-51',
      ...?overrides,
    };

    test('reads every field a real, data-rich asset record actually has', () {
      final detail = AssetDetail.fromAssetRecord(record())!;
      expect(detail.id, 'asset-77');
      expect(detail.assetReferenceId, 'AST009');
      expect(detail.assetName, 'UPS Battery Backup');
      expect(detail.manufacturer, 'APC');
      expect(detail.model, 'Smart-UPS 3000VA');
      expect(detail.serialNumber, 'APC-UPS-001-2022');
      // `qrCode` on this shape, not `barcode` like the c2o shape.
      expect(detail.barcode, 'QR-UPS-001');
      expect(detail.condition, 'good');
      expect(detail.isMaintainable, true);
      expect(detail.description, 'Uninterruptible power supply for critical equipment');
      expect(detail.warrantyExpiryDate, DateTime.parse('2025-02-28T00:00:00.000Z'));
    });

    test('no structured location walk on this shape — flatLocation carries it instead', () {
      final detail = AssetDetail.fromAssetRecord(record())!;
      expect(detail.locationPath, isEmpty);
      expect(detail.flatLocation, 'Fusion Eco Tower A - First Floor - Open Workspace A');
    });

    test('"non-maintainable" reads as false, not null', () {
      final detail = AssetDetail.fromAssetRecord(record(overrides: {'maintainability': 'non-maintainable'}))!;
      expect(detail.isMaintainable, false);
    });

    test('a missing maintainability reads as unknown (null), not false', () {
      final detail = AssetDetail.fromAssetRecord(record(overrides: {'maintainability': null}))!;
      expect(detail.isMaintainable, isNull);
    });

    test('parses the floor id (FR-2.8)', () {
      final detail = AssetDetail.fromAssetRecord(record())!;
      expect(detail.floorId, 'floor-51');
    });

    test('a record with no id returns null rather than throwing', () {
      expect(AssetDetail.fromAssetRecord({'assetName': 'No Id'}), isNull);
    });
  });

  group('FR-2.4 warranty verdict', () {
    test('a past date verdicts as expired, with the date spelled out', () {
      final v = warrantyVerdict(DateTime(2025, 6, 12), now: DateTime(2026, 9, 21));
      expect(v.status, WarrantyStatus.expired);
      expect(v.formattedDate, '12/06/2025');
    });

    test('a future date verdicts as a day count', () {
      final v = warrantyVerdict(DateTime(2026, 11, 3), now: DateTime(2026, 9, 21));
      expect(v.status, WarrantyStatus.active);
      expect(v.daysRemaining, 43);
    });

    test('exactly one day left is still the active/day-count status', () {
      final v = warrantyVerdict(DateTime(2026, 9, 22), now: DateTime(2026, 9, 21));
      expect(v.status, WarrantyStatus.active);
      expect(v.daysRemaining, 1);
    });

    test('today is its own status, not "0 days remaining"', () {
      final v = warrantyVerdict(DateTime(2026, 9, 21), now: DateTime(2026, 9, 21));
      expect(v.status, WarrantyStatus.expiresToday);
    });

    test('no date recorded is its own status, not a crash or "Invalid Date"', () {
      expect(warrantyVerdict(null).status, WarrantyStatus.none);
    });
  });
}
