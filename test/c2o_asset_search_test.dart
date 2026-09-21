import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/c2o/c2o_asset_search.dart';
import 'package:technician_portal/core/offline/offline_db.dart';

CachedC2oAsset _asset({
  required String id,
  String? reference,
  String? name,
  String? serial,
  String? space,
}) => CachedC2oAsset(
  assetId: id,
  assetReferenceId: reference,
  claims: {
    'asset': {
      'assetName': name,
      'serialNumber': serial,
      'space': space,
    },
  },
  cachedAt: DateTime.now(),
);

void main() {
  group('FR-1.6 manual search over the cached route', () {
    final chiller = _asset(
      id: 'asset-1',
      reference: 'AST228',
      name: 'FR-1.1 Test Chiller',
      serial: 'SN27673571',
      space: 'Plant Room B1',
    );
    final pump = _asset(
      id: 'asset-2',
      reference: 'AST229',
      name: 'FR-1.2 Test Pump',
      serial: 'SNPUMP002',
      space: 'Roof Level 2',
    );
    final route = [chiller, pump];

    test('an empty query returns the whole route, not nothing', () {
      expect(searchCachedAssets(route, ''), route);
      expect(searchCachedAssets(route, '   '), route);
    });

    test('matches by asset reference id', () {
      expect(searchCachedAssets(route, 'AST228'), [chiller]);
    });

    test('matches by the real asset id too', () {
      expect(searchCachedAssets(route, 'asset-2'), [pump]);
    });

    test('matches by serial number', () {
      expect(searchCachedAssets(route, '27673571'), [chiller]);
    });

    test('matches by room/space (FR-1.6\'s "room" search)', () {
      expect(searchCachedAssets(route, 'Roof'), [pump]);
    });

    test('matches by asset name', () {
      expect(searchCachedAssets(route, 'chiller'), [chiller]);
    });

    test('is case-insensitive', () {
      expect(searchCachedAssets(route, 'ast228'), [chiller]);
    });

    test('a query matching nothing returns an empty list, not the whole route', () {
      expect(searchCachedAssets(route, 'nonexistent-asset-xyz'), isEmpty);
    });
  });
}
