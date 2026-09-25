import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/snag/snag_rules.dart';
import 'package:technician_portal/domain/snag.dart';

const fixer = 'fixer-1';
const inspector = 'inspector-2';

Snag snag({
  String id = 's1',
  SnagStatus status = SnagStatus.open,
  String trade = 'electrical',
  String issueType = 'defect',
  SnagPriority priority = SnagPriority.minor,
  String title = 'Socket faceplate cracked',
  String? buildingId = 'b1',
  String? floorId = 'f1',
  String? spaceId = 'r1',
  String? assetId,
  SnagPin? pin,
  String? surveyId,
  String? raisedBy = inspector,
  String? readyBy,
  DateTime? readyAt,
  String? assignedToUserId,
  DateTime? dueDate,
  int reopenedCount = 0,
  List<SnagEvidence> evidence = const [],
  DateTime? updatedAt,
}) {
  final t = updatedAt ?? DateTime(2026, 9, 1);
  return Snag(
    id: id,
    context: SnagContext.fmTakeover,
    issueType: issueType,
    trade: trade,
    priority: priority,
    title: title,
    status: status,
    buildingId: buildingId,
    floorId: floorId,
    spaceId: spaceId,
    assetId: assetId,
    pin: pin,
    surveyId: surveyId,
    raisedBy: raisedBy,
    readyBy: readyBy,
    readyAt: readyAt,
    assignedToUserId: assignedToUserId,
    dueDate: dueDate,
    reopenedCount: reopenedCount,
    evidence: evidence,
    createdAt: t,
    updatedAt: t,
  );
}

SnagEvidence photo(String stage) =>
    SnagEvidence(id: 'e-$stage', kind: 'photo', stage: stage, capturedAt: DateTime(2026, 9, 2));

SnagTransitionResult act(Snag s, SnagAction a, {String actor = fixer, String? reason, List<SnagEvidence> added = const [], String role = 'Technician'}) =>
    SnagRules.apply(s, a, actorId: actor, actorRole: role, reason: reason, added: added, activityId: 'act', now: DateTime(2026, 9, 3));

void main() {
  group('SnagRules.apply — mirrors server snagRules.ts', () {
    test('ready needs an after photo (false completion)', () {
      final r = act(snag(), SnagAction.ready);
      expect(r.ok, isFalse);
      expect(r.failure!.code, 'AFTER_PHOTO_REQUIRED');
    });

    test('ready with an after photo records who and when, and logs the event', () {
      final r = act(snag(status: SnagStatus.inProgress), SnagAction.ready, added: [photo('after')]);
      expect(r.ok, isTrue);
      expect(r.snag!.status, SnagStatus.ready);
      expect(r.snag!.readyBy, fixer);
      expect(r.snag!.readyAt, DateTime(2026, 9, 3));
      expect(r.snag!.afterPhotos, hasLength(1));
      expect(r.snag!.activity.last.type, 'ready');
    });

    test('the person who marked it ready cannot verify it', () {
      final ready = snag(status: SnagStatus.ready, readyBy: fixer);
      expect(act(ready, SnagAction.verify, actor: fixer).failure!.code, 'SELF_VERIFY');
      final ok = act(ready, SnagAction.verify, actor: inspector);
      expect(ok.snag!.status, SnagStatus.closed);
      expect(ok.snag!.verifiedBy, inspector);
      expect(ok.snag!.closedAt, isNotNull);
    });

    test('reject needs a reason, reopens, counts, and clears the ready stamp', () {
      final ready = snag(status: SnagStatus.ready, readyBy: fixer, readyAt: DateTime(2026, 9, 2), reopenedCount: 1);
      expect(act(ready, SnagAction.reject, actor: inspector).failure!.code, 'REASON_REQUIRED');
      final r = act(ready, SnagAction.reject, actor: inspector, reason: 'Still sparking');
      expect(r.snag!.status, SnagStatus.open);
      expect(r.snag!.reopenedCount, 2);
      expect(r.snag!.readyBy, isNull);
      expect(r.snag!.readyAt, isNull);
      expect(r.snag!.activity.last.reason, 'Still sparking');
    });

    test('reopen only from closed; waive is admin-only', () {
      expect(act(snag(), SnagAction.reopen, reason: 'x').failure!.code, 'INVALID_TRANSITION');
      expect(act(snag(status: SnagStatus.closed), SnagAction.reopen, reason: 'Came back').snag!.status, SnagStatus.open);
      expect(act(snag(), SnagAction.waive, reason: 'ok').failure!.code, 'WAIVE_FORBIDDEN');
      expect(act(snag(), SnagAction.waive, reason: 'Client accepted', role: 'Admin').snag!.status, SnagStatus.waived);
    });

    test('actionsFor hides verify from the fixer and never offers waive', () {
      final ready = snag(status: SnagStatus.ready, readyBy: fixer);
      expect(SnagRules.actionsFor(ready, fixer), isEmpty);
      expect(SnagRules.actionsFor(ready, inspector), [SnagAction.verify, SnagAction.reject]);
      for (final s in SnagStatus.values) {
        expect(SnagRules.actionsFor(snag(status: s), inspector), isNot(contains(SnagAction.waive)));
      }
    });
  });

  group('SnagDuplicateFinder', () {
    const draft = SnagDraftSignature(
      trade: 'electrical',
      buildingId: 'b1',
      floorId: 'f1',
      spaceId: 'r1',
      issueType: 'defect',
      title: 'Cracked socket faceplate',
      raisedBy: 'someone-else',
    );

    test('same room + trade + similar words is flagged', () {
      final hits = SnagDuplicateFinder.find(draft, [snag()]);
      expect(hits, hasLength(1));
      expect(hits.single.reasons, containsAll(['space', 'trade', 'words']));
    });

    test('same room + trade alone is NOT enough — two electrical defects in a room are common', () {
      const bare = SnagDraftSignature(trade: 'electrical', buildingId: 'b1', floorId: 'f1', spaceId: 'r1');
      expect(SnagDuplicateFinder.find(bare, [snag(issueType: 'missing', title: 'Light fitting missing')]), isEmpty);
    });

    test('a close pin tips a same-room match over the bar', () {
      const pinned = SnagDraftSignature(
        trade: 'electrical',
        buildingId: 'b1',
        floorId: 'f1',
        spaceId: 'r1',
        pin: SnagPin(floorId: 'f1', x: 0.50, y: 0.50),
      );
      final existing = snag(title: 'x', issueType: 'damage', pin: const SnagPin(floorId: 'f1', x: 0.51, y: 0.51));
      expect(SnagDuplicateFinder.find(pinned, [existing]), hasLength(1));
    });

    test('closed snags, other rooms and my own snags from this walk are never offered', () {
      final pool = [
        snag(id: 'closed', status: SnagStatus.closed),
        snag(id: 'other-room', spaceId: 'r9'),
        snag(id: 'mine', surveyId: 'w1', raisedBy: 'me'),
      ];
      const mineDraft = SnagDraftSignature(
        trade: 'electrical',
        buildingId: 'b1',
        floorId: 'f1',
        spaceId: 'r1',
        issueType: 'defect',
        title: 'Cracked socket faceplate',
        surveyId: 'w1',
        raisedBy: 'me',
      );
      expect(SnagDuplicateFinder.find(mineDraft, pool), isEmpty);
    });

    test('the same asset matches across rooms', () {
      const d = SnagDraftSignature(trade: 'hvac', buildingId: 'b1', spaceId: 'r1', assetId: 'ahu-1', issueType: 'defect');
      final s = snag(trade: 'hvac', spaceId: 'plant-room', assetId: 'ahu-1');
      expect(SnagDuplicateFinder.find(d, [s]), hasLength(1));
    });

    test('word similarity ignores stop words and case', () {
      expect(SnagDuplicateFinder.wordSimilarity('The door closer is MISSING', 'door closer missing'), 1.0);
      expect(SnagDuplicateFinder.wordSimilarity('', 'door'), 0);
    });
  });

  group('SnagReadinessCalculator — unmeasured is not passed', () {
    test('nothing raised and no survey: no score at all', () {
      final r = SnagReadinessCalculator.compute(snags: const []);
      expect(r.score, isNull);
      expect(r.dimensions.every((d) => !d.measured), isTrue);
    });

    test('a clean survey with full coverage and no snags scores on coverage alone', () {
      final r = SnagReadinessCalculator.compute(snags: const [], spacesInScope: 10, spacesInspected: 10);
      expect(r.score, 1.0);
      expect(r.evaluatedWeight, closeTo(0.3, 1e-9));
    });

    test('an open critical drags the blockers dimension, waived ones are ignored', () {
      final r = SnagReadinessCalculator.compute(
        snags: [
          snag(id: 'a', priority: SnagPriority.critical),
          snag(id: 'b', priority: SnagPriority.critical, status: SnagStatus.closed),
          snag(id: 'c', status: SnagStatus.waived, priority: SnagPriority.critical),
        ],
      );
      final blockers = r.dimensions.firstWhere((d) => d.key == 'blockers');
      expect(blockers.score, 0.5);
      expect(blockers.detail, '1/2');
      final closure = r.dimensions.firstWhere((d) => d.key == 'closure');
      expect(closure.score, 0.5);
    });

    test('reopens lower first-time-fix quality', () {
      final r = SnagReadinessCalculator.compute(
        snags: [
          snag(id: 'a', status: SnagStatus.closed),
          snag(id: 'b', status: SnagStatus.open, reopenedCount: 1),
        ],
      );
      expect(r.dimensions.firstWhere((d) => d.key == 'quality').score, 0.5);
    });
  });

  group('SnagQueues', () {
    test('waitingOn: verify first, then fixes by severity, then my overdue; each snag once', () {
      final now = DateTime(2026, 9, 10);
      final items = SnagQueues.waitingOn(
        'me',
        [
          snag(id: 'fix-minor', assignedToUserId: 'me', priority: SnagPriority.minor),
          snag(id: 'verify', status: SnagStatus.ready, readyBy: 'someone'),
          snag(id: 'fix-critical', assignedToUserId: 'me', priority: SnagPriority.critical),
          snag(id: 'overdue', raisedBy: 'me', dueDate: DateTime(2026, 9, 1)),
          snag(id: 'my-own-fix', status: SnagStatus.ready, readyBy: 'me'),
        ],
        now: now,
      );
      expect(items.map((i) => i.snag.id), ['verify', 'fix-critical', 'fix-minor', 'overdue']);
    });

    test('sortForList: live first, then severity', () {
      final sorted = SnagQueues.sortForList([
        snag(id: 'closed-critical', status: SnagStatus.closed, priority: SnagPriority.critical),
        snag(id: 'open-minor'),
        snag(id: 'open-critical', priority: SnagPriority.critical),
      ]);
      expect(sorted.map((s) => s.id), ['open-critical', 'open-minor', 'closed-critical']);
    });
  });

  test('floorCoverage counts swept and clear rooms per floor', () {
    const tree = SnagLocationTree(
      id: 'b1',
      name: 'Tower A',
      floors: [
        SnagFloor(id: 'f1', name: 'L1', spaces: [SnagSpace(id: 'r1', name: '101'), SnagSpace(id: 'r2', name: '102')]),
      ],
    );
    final survey = SnagSurvey(
      id: 'w1',
      name: 'Walk',
      context: SnagContext.fmTakeover,
      startedAt: DateTime(2026, 9, 1),
      inspectedSpaces: [SpaceSweep(spaceId: 'r1', clear: true, snagCount: 0, at: DateTime(2026, 9, 1))],
    );
    final c = floorCoverage(tree, survey).single;
    expect(c.inspected, 1);
    expect(c.clear, 1);
    expect(c.total, 2);
    expect(c.ratio, 0.5);
  });
}
