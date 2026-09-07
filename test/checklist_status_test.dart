import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/utils/checklist_status.dart';
import 'package:technician_portal/domain/checklist.dart';

ChecklistItem item({
  bool isCompleted = false,
  bool isOther = false,
  String? startTime,
  String? endTime,
  int? timeSpent,
  List<Map<String, dynamic>> sessions = const [],
}) =>
    ChecklistItem.fromJson({
      'isCompleted': isCompleted,
      'isOther': isOther,
      'startTime': startTime,
      'endTime': endTime,
      'timeSpent': timeSpent,
      'sessions': sessions,
    });

void main() {
  group('deriveChecklistSummary', () {
    test('no actionable items is Not Started', () {
      final summary = deriveChecklistSummary([item(isOther: true)]);
      expect(summary.state, ChecklistSummaryState.notStarted);
      expect(summary.totalCount, 0);
    });

    test('untouched items are Not Started', () {
      final summary = deriveChecklistSummary([item(), item()]);
      expect(summary.state, ChecklistSummaryState.notStarted);
      expect(summary.totalCount, 2);
    });

    test('an open session makes it Started', () {
      final summary = deriveChecklistSummary([
        item(sessions: [
          {'startTime': '2026-09-04T08:00:00.000Z'}
        ]),
        item(),
      ]);
      expect(summary.state, ChecklistSummaryState.started);
      expect(summary.startedCount, 1);
    });

    test('a legacy startTime with no sessions also counts as running', () {
      final summary =
          deriveChecklistSummary([item(startTime: '2026-09-04T08:00:00.000Z')]);
      expect(summary.state, ChecklistSummaryState.started);
    });

    test('closed sessions with work left are Paused', () {
      final summary = deriveChecklistSummary([
        item(isCompleted: true),
        item(sessions: [
          {
            'startTime': '2026-09-04T08:00:00.000Z',
            'endTime': '2026-09-04T09:00:00.000Z',
          }
        ]),
      ]);
      expect(summary.state, ChecklistSummaryState.paused);
    });

    test('every actionable item done is Completed', () {
      final summary = deriveChecklistSummary([
        item(isCompleted: true),
        item(isCompleted: true),
        item(isOther: true),
      ]);
      expect(summary.state, ChecklistSummaryState.completed);
      expect(summary.completedCount, 2);
    });

    test('an incomplete Other item does not block Completed', () {
      final summary = deriveChecklistSummary([
        item(isCompleted: true),
        item(isOther: true),
      ]);
      expect(summary.state, ChecklistSummaryState.completed);
    });
  });

  group('hasAnyChecklistCompleted', () {
    test('counts a completed Other item', () {
      expect(
        hasAnyChecklistCompleted([item(), item(isOther: true, isCompleted: true)]),
        isTrue,
      );
    });

    test('is false when nothing is done', () {
      expect(hasAnyChecklistCompleted([item(), item(isOther: true)]), isFalse);
    });
  });

  group('getFirstChecklistStartTime', () {
    test('finds the earliest start across items and sessions', () {
      final first = getFirstChecklistStartTime([
        item(sessions: [
          {'startTime': '2026-09-04T10:00:00.000Z'}
        ]),
        item(sessions: [
          {'startTime': '2026-09-04T06:30:00.000Z'},
          {'startTime': '2026-09-04T12:00:00.000Z'},
        ]),
        item(startTime: '2026-09-04T08:00:00.000Z'),
      ]);
      expect(first, DateTime.parse('2026-09-04T06:30:00.000Z').toLocal());
    });

    test('is null when nothing ever started', () {
      expect(getFirstChecklistStartTime([item()]), isNull);
    });
  });

  test('getLastChecklistEndedTime finds the latest end', () {
    final last = getLastChecklistEndedTime([
      item(endTime: '2026-09-04T09:00:00.000Z'),
      item(sessions: [
        {
          'startTime': '2026-09-04T10:00:00.000Z',
          'endTime': '2026-09-04T11:30:00.000Z',
        }
      ]),
    ]);
    expect(last, DateTime.parse('2026-09-04T11:30:00.000Z').toLocal());
  });

  group('calculateChecklistsActualHours', () {
    test('prefers recorded session minutes', () {
      final hours = calculateChecklistsActualHours([
        item(sessions: [
          {'timeSpent': 30},
          {'timeSpent': 60},
        ]),
      ]);
      expect(hours, 1.5);
    });

    test('falls back to the session span when minutes are missing', () {
      final hours = calculateChecklistsActualHours([
        item(sessions: [
          {
            'startTime': '2026-09-04T08:00:00.000Z',
            'endTime': '2026-09-04T09:45:00.000Z',
          }
        ]),
      ]);
      expect(hours, 1.8);
    });

    test('uses item-level time only when there are no sessions', () {
      expect(calculateChecklistsActualHours([item(timeSpent: 90)]), 1.5);
      expect(
        calculateChecklistsActualHours([
          item(timeSpent: 90, sessions: [
            {'timeSpent': 30}
          ])
        ]),
        0.5,
      );
    });

    test('includes Other items', () {
      final hours = calculateChecklistsActualHours([
        item(isOther: true, timeSpent: 60),
        item(timeSpent: 60),
      ]);
      expect(hours, 2.0);
    });
  });

  group('isChecklistFullyComplete', () {
    test('an empty actionable list is complete', () {
      expect(isChecklistFullyComplete([item(isOther: true)]), isTrue);
    });

    test('one outstanding item is not complete', () {
      expect(
        isChecklistFullyComplete([item(isCompleted: true), item()]),
        isFalse,
      );
    });
  });

  group('legacy row shapes', () {
    test('reads task/completed and a string comment', () {
      final legacy = ChecklistItem.fromJson({
        'id': 3,
        'task': 'Check filter',
        'completed': true,
        'comments': 'Replaced during service',
      });
      expect(legacy.id, '3');
      expect(legacy.title, 'Check filter');
      expect(legacy.isCompleted, isTrue);
      expect(legacy.legacyComment, 'Replaced during service');
      expect(legacy.comments, isEmpty);
    });

    test('reads a note list', () {
      final modern = ChecklistItem.fromJson({
        'name': 'Inspect belt',
        'comments': [
          {'text': 'Frayed', 'createdAt': '2026-09-04T08:00:00.000Z'}
        ],
      });
      expect(modern.title, 'Inspect belt');
      expect(modern.comments.single.text, 'Frayed');
    });
  });
}
