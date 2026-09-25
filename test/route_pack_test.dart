import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/c2o/route_pack.dart';

void main() {
  group('RoutePackEstimate (FR-5.1 pre-download size check)', () {
    test('parses counts and formats bytes readably', () {
      final estimate = RoutePackEstimate.fromJson({
        'assetCount': 342,
        'estimatedBytes': 525312,
      });

      expect(estimate.assetCount, 342);
      expect(estimate.formattedSize, '513 KB');
    });

    test('formats small byte counts and megabyte counts', () {
      expect(const RoutePackEstimate(assetCount: 1, estimatedBytes: 500).formattedSize, '500 B');
      expect(
        const RoutePackEstimate(assetCount: 2000, estimatedBytes: 3145728).formattedSize,
        '3.0 MB',
      );
    });
  });

  group('RoutePackAsset (SR-1 per-asset payload)', () {
    test('parses the fields a route-mode list/progress view needs', () {
      final asset = RoutePackAsset.fromJson({
        'id': 'asset-1',
        'assetReferenceId': 'AST228',
        'assetName': 'FR-1.1 Test Chiller',
        'scanToken': 'b086f3fa6f236bf9',
        'verificationStatus': 'verified',
        'openFindingCount': 2,
        'lastVerification': {'result': 'mismatch', 'verifiedByName': 'Ravi'},
      });

      expect(asset.id, 'asset-1');
      expect(asset.assetReferenceId, 'AST228');
      expect(asset.verificationStatus, 'verified');
      expect(asset.openFindingCount, 2);
      expect(asset.lastVerificationResult, 'mismatch');
      // The raw payload is carried through unparsed for AssetDetail.fromClaims.
      expect(asset.raw['assetName'], 'FR-1.1 Test Chiller');
    });

    test('missing lastVerification/openFindingCount default safely', () {
      final asset = RoutePackAsset.fromJson({'id': 'asset-2'});
      expect(asset.openFindingCount, 0);
      expect(asset.lastVerificationResult, isNull);
    });
  });

  group('RoutePack (SR-2 freshness stamp)', () {
    test('parses scope/asOf/versionTag and every asset', () {
      final pack = RoutePack.fromJson({
        'scope': 'package',
        'id': 'pkg-1',
        'asOf': '2026-09-25T05:39:33.603Z',
        'versionTag': '98d7ad7e711f6e5f67e4d82a645c121a12416f18',
        'assetCount': 2,
        'assets': [
          {'id': 'asset-1'},
          {'id': 'asset-2'},
        ],
      });

      expect(pack.scope, RouteScope.package);
      expect(pack.id, 'pkg-1');
      expect(pack.versionTag, '98d7ad7e711f6e5f67e4d82a645c121a12416f18');
      expect(pack.assetCount, 2);
      expect(pack.assets.map((a) => a.id), ['asset-1', 'asset-2']);
    });

    test('an empty pack (no matching assets) parses to zero assets, not an error', () {
      final pack = RoutePack.fromJson({
        'scope': 'building',
        'id': 'bldg-1',
        'asOf': '2026-09-25T00:00:00.000Z',
        'versionTag': 'abc',
        'assetCount': 0,
        'assets': [],
      });
      expect(pack.assets, isEmpty);
    });
  });
}
