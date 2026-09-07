import '../../domain/checklist.dart';

/// Port of the web `lib/checklist-status.ts`. Every rule here also runs on the
/// server, so the derivations must stay byte-for-byte equivalent.
enum ChecklistSummaryState {
  notStarted('Not Started'),
  started('Started'),
  paused('Paused'),
  completed('Completed');

  const ChecklistSummaryState(this.label);
  final String label;
}

class ChecklistSummary {
  const ChecklistSummary({
    required this.state,
    required this.startedCount,
    required this.completedCount,
    required this.totalCount,
  });

  final ChecklistSummaryState state;
  final int startedCount;
  final int completedCount;
  final int totalCount;

  double get progress => totalCount == 0 ? 0 : completedCount / totalCount;
}

/// "Other" items are excluded from progress — they are ad-hoc extras, not the
/// scope of work the record was raised for.
ChecklistSummary deriveChecklistSummary(List<ChecklistItem> items) {
  final actionable = items.where((i) => !i.isOther).toList();
  final totalCount = actionable.length;
  final completedCount = actionable.where((i) => i.isCompleted).length;
  final startedCount = actionable.where((item) {
    final activeSession = item.sessions.any((s) => s.endTime == null);
    final legacyRunning =
        item.startTime != null && item.endTime == null && item.sessions.isEmpty;
    return activeSession || legacyRunning;
  }).length;

  if (totalCount == 0) {
    return const ChecklistSummary(
      state: ChecklistSummaryState.notStarted,
      startedCount: 0,
      completedCount: 0,
      totalCount: 0,
    );
  }

  if (completedCount == totalCount) {
    return ChecklistSummary(
      state: ChecklistSummaryState.completed,
      startedCount: startedCount,
      completedCount: completedCount,
      totalCount: totalCount,
    );
  }

  if (startedCount > 0) {
    return ChecklistSummary(
      state: ChecklistSummaryState.started,
      startedCount: startedCount,
      completedCount: completedCount,
      totalCount: totalCount,
    );
  }

  final hasAnyActivity = actionable.any(
    (i) => i.isCompleted || i.sessions.isNotEmpty || i.startTime != null,
  );

  return ChecklistSummary(
    state: hasAnyActivity
        ? ChecklistSummaryState.paused
        : ChecklistSummaryState.notStarted,
    startedCount: startedCount,
    completedCount: completedCount,
    totalCount: totalCount,
  );
}

bool isChecklistFullyComplete(List<ChecklistItem> items) {
  final actionable = items.where((i) => !i.isOther);
  return actionable.isEmpty || actionable.every((i) => i.isCompleted);
}

/// At least one item done — "Other" included. A record can never close with
/// zero checklist activity, even when `checklistMandatory` is false.
bool hasAnyChecklistCompleted(List<ChecklistItem> items) =>
    items.any((i) => i.isCompleted);

/// Earliest start across every item's sessions. Technicians work items out of
/// order, so a record started when its FIRST checklist item did, not when a
/// button was pressed. Feeds the downtime calculation.
DateTime? getFirstChecklistStartTime(List<ChecklistItem> items) {
  DateTime? earliest;
  for (final item in items) {
    final candidates = <DateTime?>[
      item.startTime,
      for (final s in item.sessions) s.startTime,
    ];
    for (final c in candidates) {
      if (c == null) continue;
      if (earliest == null || c.isBefore(earliest)) earliest = c;
    }
  }
  return earliest;
}

/// Latest end across every item's sessions.
DateTime? getLastChecklistEndedTime(List<ChecklistItem> items) {
  DateTime? latest;
  for (final item in items) {
    final candidates = <DateTime?>[
      item.endTime,
      for (final s in item.sessions) s.endTime,
    ];
    for (final c in candidates) {
      if (c == null) continue;
      if (latest == null || c.isAfter(latest)) latest = c;
    }
  }
  return latest;
}

/// Sum of tracked time in hours, 1 dp — "Other" items included. Single source
/// of truth for `actualHours`.
double calculateChecklistsActualHours(List<ChecklistItem> items) {
  var totalMinutes = 0.0;
  for (final item in items) {
    if (item.sessions.isNotEmpty) {
      for (final session in item.sessions) {
        final spent = session.timeSpent;
        if (spent != null && spent > 0) {
          totalMinutes += spent;
        } else if (session.startTime != null && session.endTime != null) {
          final diff = session.endTime!
                  .difference(session.startTime!)
                  .inMilliseconds /
              (1000 * 60);
          if (diff > 0) totalMinutes += diff;
        }
      }
    } else if (item.timeSpent != null && item.timeSpent! > 0) {
      totalMinutes += item.timeSpent!;
    } else if (item.startTime != null && item.endTime != null) {
      final diff =
          item.endTime!.difference(item.startTime!).inMilliseconds / (1000 * 60);
      if (diff > 0) totalMinutes += diff;
    }
  }
  return (totalMinutes / 60 * 10).round() / 10;
}
