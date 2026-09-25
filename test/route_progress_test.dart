import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/c2o/route_progress.dart';

Map<String, dynamic> _claims({
  String? assetName,
  String? verificationStatus,
  List<Map<String, dynamic>>? locationPath,
}) => {
  'asset': {
    'id': 'irrelevant',
    'assetName': assetName,
    'verificationStatus': verificationStatus,
    'locationPath': locationPath ?? const [],
  },
};

void main() {
  group('routeAssetRowFromClaims', () {
    test('reads name, status and the Room step of the location walk', () {
      final row = routeAssetRowFromClaims(
        assetId: 'asset-1',
        claims: _claims(
          assetName: 'Chiller 01',
          verificationStatus: 'verified',
          locationPath: [
            {'level': 'Building', 'label': 'Tower A', 'code': null},
            {'level': 'Room', 'label': 'Plant Room 3', 'code': 'R-303'},
          ],
        ),
      );

      expect(row.name, 'Chiller 01');
      expect(row.status, 'verified');
      // Code wins over label — same convention as the plan's wayfinding note.
      expect(row.roomLabel, 'R-303');
    });

    test('falls back to the room label when there is no code', () {
      final row = routeAssetRowFromClaims(
        assetId: 'asset-1',
        claims: _claims(
          locationPath: [
            {'level': 'Room', 'label': 'Plant Room 3', 'code': null},
          ],
        ),
      );
      expect(row.roomLabel, 'Plant Room 3');
    });

    test('an asset with no Room step at all has a null roomLabel', () {
      final row = routeAssetRowFromClaims(
        assetId: 'asset-1',
        claims: _claims(
          locationPath: [
            {'level': 'Building', 'label': 'Tower A', 'code': null},
          ],
        ),
      );
      expect(row.roomLabel, isNull);
    });

    test('a missing status defaults to pending, not a crash', () {
      final row = routeAssetRowFromClaims(assetId: 'asset-1', claims: _claims());
      expect(row.status, 'pending');
      expect(row.isOutstanding, isTrue);
    });

    test('falls back to assetReferenceId when the register has no name', () {
      final row = routeAssetRowFromClaims(
        assetId: 'asset-1',
        assetReferenceId: 'AST228',
        claims: _claims(),
      );
      expect(row.name, 'AST228');
    });
  });

  group('RouteAssetRow status buckets (FR-5.3)', () {
    test('verified means verified, nothing else', () {
      const row = RouteAssetRow(id: '1', name: null, roomLabel: null, status: 'verified');
      expect(row.isVerified, isTrue);
      expect(row.isFlagged, isFalse);
      expect(row.isOutstanding, isFalse);
    });

    for (final flaggedStatus in ['mismatch', 'missing']) {
      test('"$flaggedStatus" is flagged, not outstanding', () {
        final row = RouteAssetRow(id: '1', name: null, roomLabel: null, status: flaggedStatus);
        expect(row.isFlagged, isTrue);
        expect(row.isOutstanding, isFalse);
      });
    }

    test('"pending" (or anything else) is outstanding', () {
      const row = RouteAssetRow(id: '1', name: null, roomLabel: null, status: 'pending');
      expect(row.isOutstanding, isTrue);
    });
  });

  group('RouteProgress.from (FR-5.3)', () {
    test('tallies verified/outstanding/flagged correctly', () {
      final rows = [
        const RouteAssetRow(id: '1', name: null, roomLabel: null, status: 'verified'),
        const RouteAssetRow(id: '2', name: null, roomLabel: null, status: 'verified'),
        const RouteAssetRow(id: '3', name: null, roomLabel: null, status: 'pending'),
        const RouteAssetRow(id: '4', name: null, roomLabel: null, status: 'mismatch'),
        const RouteAssetRow(id: '5', name: null, roomLabel: null, status: 'missing'),
      ];

      final progress = RouteProgress.from(rows);

      expect(progress.verified, 2);
      expect(progress.outstanding, 1);
      expect(progress.flagged, 2);
      expect(progress.total, 5);
    });

    test('an empty route has all-zero progress, not an error', () {
      final progress = RouteProgress.from(const []);
      expect(progress.total, 0);
    });
  });

  group('groupRouteAssetsByRoom / sortRoomNames (FR-5.2)', () {
    test('groups by room label and buckets no-room assets under the unassigned label', () {
      final rows = [
        const RouteAssetRow(id: '1', name: 'A', roomLabel: 'R-101', status: 'pending'),
        const RouteAssetRow(id: '2', name: 'B', roomLabel: 'R-101', status: 'verified'),
        const RouteAssetRow(id: '3', name: 'C', roomLabel: null, status: 'pending'),
      ];

      final grouped = groupRouteAssetsByRoom(rows, unassignedLabel: 'Unassigned');

      expect(grouped['R-101']!.map((r) => r.id), ['1', '2']);
      expect(grouped['Unassigned']!.map((r) => r.id), ['3']);
    });

    test('sortRoomNames is alphabetical with Unassigned always last', () {
      final sorted = sortRoomNames(
        ['R-303', 'Unassigned', 'R-101', 'R-202'],
        unassignedLabel: 'Unassigned',
      );
      expect(sorted, ['R-101', 'R-202', 'R-303', 'Unassigned']);
    });

    test('Unassigned stays last even when it would sort first alphabetically', () {
      // Regression guard: a naive plain sort would put "Unassigned" before
      // any room starting with a later letter — this must not happen.
      final sorted = sortRoomNames(['Zebra Room', 'Unassigned'], unassignedLabel: 'Unassigned');
      expect(sorted, ['Zebra Room', 'Unassigned']);
    });
  });
}
