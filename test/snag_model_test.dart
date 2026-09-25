import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/app/router.dart';
import 'package:technician_portal/domain/snag.dart';

void main() {
  group('Snag.fromJson — server DTO', () {
    final server = {
      'id': '4f0c7a8e-1111-4222-8333-444455556666',
      'number': 42,
      'reference': 'SN-00042',
      'context': 'fm-takeover',
      'issueType': 'damage',
      'trade': 'doors-windows',
      'priority': 'major',
      'severity': 'warning',
      'title': 'Door closer missing',
      'description': null,
      'status': 'ready',
      'buildingId': 'b1',
      'pin': {'kind': 'plan', 'floorId': 'f1', 'x': '0.25', 'y': 0.75},
      'evidence': [
        {'id': 'e1', 'kind': 'photo', 'stage': 'before', 'url': 'https://minio/x.jpg', 'geo': {'lat': 25.2, 'lng': 55.3}},
        {'id': 'e2', 'kind': 'photo', 'stage': 'after', 'url': '__pending_snag_e2__'},
        {'id': 'e3', 'kind': 'audio', 'stage': 'before', 'url': 'https://minio/n.m4a'},
      ],
      'activity': [
        {'id': 'a1', 'at': '2026-09-01T10:00:00.000Z', 'type': 'raised', 'byName': 'Sam'},
      ],
      'reopenedCount': '2',
      'reportCount': 3,
      'clientCreatedAt': '2026-09-01T09:59:00.000Z',
      'createdAt': '2026-09-01T12:00:00.000Z',
      'updatedAt': '2026-09-02T12:00:00.000Z',
    };

    test('parses vocabulary, numbers-as-strings and the pin', () {
      final s = Snag.fromJson(server);
      expect(s.displayRef, 'SN-00042');
      expect(s.context, SnagContext.fmTakeover);
      expect(s.priority, SnagPriority.major);
      expect(s.status, SnagStatus.ready);
      expect(s.reopenedCount, 2);
      expect(s.reportCount, 3);
      expect(s.pin!.x, 0.25);
      expect(s.localOnly, isFalse);
    });

    test('capture time wins over the server insert time — an offline walk syncs hours later', () {
      expect(Snag.fromJson(server).createdAt, DateTime.parse('2026-09-01T09:59:00.000Z').toLocal());
    });

    test('an unsubstituted upload placeholder is not treated as a URL', () {
      final s = Snag.fromJson(server);
      expect(s.evidence[1].url, isNull);
      expect(s.photos, hasLength(2));
      expect(s.beforePhotos.single.lat, 25.2);
      expect(s.afterPhotos.single.id, 'e2');
      expect(s.coverPhoto!.id, 'e1');
    });

    test('unknown words fall back instead of throwing', () {
      final s = Snag.fromJson({'id': 'x', 'status': 'weird', 'priority': 'urgent', 'context': '??'});
      expect(s.status, SnagStatus.open);
      expect(s.priority, SnagPriority.minor);
      expect(s.context, SnagContext.operations);
      expect(s.title, 'Snag');
      expect(s.displayRef, '#x');
    });

    test('local storage round-trip keeps localPath and the localOnly flag', () {
      final local = Snag.fromJson(server).copyWith(
        localOnly: true,
        evidence: [
          SnagEvidence(id: 'e9', kind: 'photo', stage: 'before', capturedAt: DateTime(2026), localPath: '/tmp/e9.jpg'),
        ],
      );
      final back = Snag.fromJson(local.toJson());
      expect(back.localOnly, isTrue);
      expect(back.evidence.single.localPath, '/tmp/e9.jpg');
      expect(back.displayRef, 'SN-00042');
      expect(back.pin!.floorId, 'f1');
    });

    test('isOverdue only for open or in-progress snags past due', () {
      final base = Snag.fromJson({...server, 'status': 'open', 'dueDate': '2026-09-01T00:00:00.000Z'});
      expect(base.isOverdue(DateTime(2026, 9, 5)), isTrue);
      expect(base.copyWith(status: SnagStatus.ready).isOverdue(DateTime(2026, 9, 5)), isFalse);
    });
  });

  test('SnagSuggestion drops values outside the vocabulary', () {
    final s = SnagSuggestion.fromJson({'trade': 'plasterwork', 'issueType': 'damage', 'priority': 'critical'});
    expect(s.trade, isNull);
    expect(s.issueType, 'damage');
    expect(s.priority, SnagPriority.critical);
  });

  test('SnagLocationTree.locate finds the room and its floor', () {
    final tree = SnagLocationTree.fromJson({
      'id': 'b1',
      'name': 'Tower A',
      'floors': [
        {
          'id': 'f2',
          'name': 'Level 2',
          'hasPlan': true,
          'spaces': [
            {'id': 'r204', 'name': 'Room 204', 'ref': 'SP-204'},
          ],
        },
      ],
    });
    final (floor, space) = tree.locate('r204')!;
    expect(floor.name, 'Level 2');
    expect(space.ref, 'SP-204');
    expect(tree.spaceCount, 1);
    expect(tree.locate('nope'), isNull);
  });

  group('Routes', () {
    test('snagNew carries context as query params and nothing when empty', () {
      expect(Routes.snagNew(), '/snags/new');
      final r = Uri.parse(Routes.snagNew(assetId: 'a1', assetName: 'AHU 1', workOrderId: 'w1', context: 'operations'));
      expect(r.path, '/snags/new');
      expect(r.queryParameters, {'assetId': 'a1', 'assetName': 'AHU 1', 'workOrderId': 'w1', 'context': 'operations'});
    });

    test('snag paths mirror the server notification link /technician/snags/<id>', () {
      expect(Routes.snagDetail('abc'), '/snags/abc');
      expect(Uri.parse(Routes.snagVerify('b1')).queryParameters['buildingId'], 'b1');
    });
  });
}
