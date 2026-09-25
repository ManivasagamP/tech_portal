import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/c2o/assigned_route.dart';
import 'package:technician_portal/core/c2o/route_pack.dart';
import 'package:technician_portal/core/offline/offline_db.dart';

const _pkg = 'a56b49c6-0d6d-4092-a015-22ee1e10fcb2';

Map<String, dynamic> _row({Object? scope = 'package', Object? label = 'FR-1.1 Test Package'}) => {
  'id': 'assign-1',
  'scope': scope,
  'scopeId': _pkg,
  'packageId': _pkg,
  'projectId': null,
  'technicianId': 'tech-1',
  'label': label,
  'assetCount': 2,
  'assignedAt': '2026-09-25T10:00:00.000Z',
};

DownloadedRoutePack _downloaded(RouteScope scope, String id) => DownloadedRoutePack(
  scope: scope,
  id: id,
  asOf: DateTime.now(),
  versionTag: 'v1',
  assetIds: const ['a', 'b'],
  downloadedAt: DateTime.now(),
);

void main() {
  group('AssignedRoute.fromJson', () {
    test('reads the server view, including the readable label', () {
      final route = AssignedRoute.fromJson(_row())!;
      expect(route.scope, RouteScope.package);
      expect(route.scopeId, _pkg);
      expect(route.packageId, _pkg);
      expect(route.label, 'FR-1.1 Test Package');
      expect(route.assetCount, 2);
      expect(route.assignedAt, DateTime.utc(2026, 9, 25, 10));
    });

    test('an unknown scope from a newer server is skipped, not a crash', () {
      expect(AssignedRoute.fromJson(_row(scope: 'campus')), isNull);
    });

    test('a missing label falls back to the scope id', () {
      expect(AssignedRoute.fromJson(_row(label: null))!.label, _pkg);
    });

    test('a null asset count stays null (route unresolvable at list time)', () {
      final json = _row()..['assetCount'] = null;
      expect(AssignedRoute.fromJson(json)!.assetCount, isNull);
    });
  });

  group('parseAssignedRoutes', () {
    test('one bad row never hides the rest of the list', () {
      final routes = parseAssignedRoutes([_row(), 'garbage', _row(scope: 'campus'), _row()]);
      expect(routes, hasLength(2));
    });

    test('a non-list body is an empty list', () {
      expect(parseAssignedRoutes({'message': 'oops'}), isEmpty);
      expect(parseAssignedRoutes(null), isEmpty);
    });
  });

  group('FR-5.8 hand-off fields', () {
    test('progress becomes a checked count (verified + flagged)', () {
      final json = _row()..['progress'] = {'total': 2, 'verified': 1, 'flagged': 1, 'pending': 0};
      expect(AssignedRoute.fromJson(json)!.checkedCount, 2);
    });

    test('an older server with no progress leaves the count unknown', () {
      expect(AssignedRoute.fromJson(_row())!.checkedCount, isNull);
    });

    test('a hand-off names who it came from', () {
      final json = _row()
        ..['handedOverFrom'] = {'technicianId': 't2', 'name': 'Rajesh', 'checkedCount': 1};
      final route = AssignedRoute.fromJson(json)!;
      expect(route.isHandOver, isTrue);
      expect(route.handedOverFromName, 'Rajesh');
    });

    test('a hand-off from a deleted account still reads as a hand-off', () {
      final json = _row()..['handedOverFrom'] = {'technicianId': 't2', 'name': null};
      expect(AssignedRoute.fromJson(json)!.isHandOver, isTrue);
    });

    test('no hand-off is not a hand-off', () {
      final json = _row()..['handedOverFrom'] = null;
      expect(AssignedRoute.fromJson(json)!.isHandOver, isFalse);
    });
  });

  group('queuedChecksForRoute', () {
    PendingMutation m(String url, {String? type = 'Asset', String? id}) => PendingMutation(
      clientMutationId: '$url-$id',
      method: 'post',
      url: url,
      body: null,
      label: 'x',
      attempts: 0,
      createdAt: DateTime(2026),
      entityType: type,
      entityId: id,
    );
    final pack = _downloaded(RouteScope.package, _pkg); // assets a, b

    test('counts only verify submissions for this route\'s assets', () {
      final queue = [
        m('/api/c2o/assets/a/verify', id: 'a'),
        m('/api/c2o/assets/b/verify', id: 'b'),
        m('/api/c2o/assets/z/verify', id: 'z'), // another route
        m('/api/fm/work-orders/a/notes', type: 'WorkOrder', id: 'a'), // not a check
      ];
      expect(queuedChecksForRoute(pack, queue), 2);
    });

    test('no pack on the phone means nothing to warn about', () {
      expect(queuedChecksForRoute(null, [m('/api/c2o/assets/a/verify', id: 'a')]), 0);
    });
  });

  group('isDownloadedIn', () {
    final route = AssignedRoute.fromJson(_row())!;

    test('matches on the same (scope, id) the downloaded table keys on', () {
      expect(route.isDownloadedIn([_downloaded(RouteScope.package, _pkg)]), isTrue);
    });

    test('same id under a different scope is not a match', () {
      expect(route.isDownloadedIn([_downloaded(RouteScope.building, _pkg)]), isFalse);
    });

    test('nothing downloaded means not downloaded', () {
      expect(route.isDownloadedIn(const []), isFalse);
    });
  });
}
