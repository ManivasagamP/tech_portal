import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/dates.dart';
import '../domain/maintenance_record.dart';
import 'auth_controller.dart';
import 'orders_controller.dart';

/// The technician's work bucketed by the day it is due. Preventive is absent
/// on purpose — it is not browsable, and only reachable from an invite.
final calendarRecordsProvider =
    FutureProvider<List<MaintenanceRecord>>((ref) async {
  final session = ref.watch(authControllerProvider).session;
  if (session == null || session.userId.isEmpty) return const [];
  final page = await ref.watch(ordersRepositoryProvider).listAll(session.userId);
  return page.records;
});

/// `yyyy-MM-dd` → the records due that day, each day's list in due order.
Map<String, List<MaintenanceRecord>> bucketByDay(
  List<MaintenanceRecord> records,
) {
  final buckets = <String, List<MaintenanceRecord>>{};
  for (final record in records) {
    final due = record.effectiveDate;
    if (due == null) continue;
    buckets.putIfAbsent(formatDayKey(due), () => []).add(record);
  }
  for (final day in buckets.values) {
    day.sort((a, b) {
      final left = a.effectiveDate;
      final right = b.effectiveDate;
      if (left == null || right == null) return 0;
      return left.compareTo(right);
    });
  }
  return buckets;
}

/// Every cell of a month grid, including the neighbouring days that pad the
/// first and last weeks out. Weeks start on Sunday, as the web's does.
List<DateTime> monthGrid(DateTime month) {
  final firstOfMonth = DateTime(month.year, month.month);
  final lastOfMonth = DateTime(month.year, month.month + 1, 0);

  // DateTime.weekday is 1 (Monday) to 7 (Sunday); Sunday must map to 0.
  final leading = firstOfMonth.weekday % 7;
  final start = firstOfMonth.subtract(Duration(days: leading));
  final trailing = 6 - (lastOfMonth.weekday % 7);
  final end = lastOfMonth.add(Duration(days: trailing));

  final days = <DateTime>[];
  for (var day = start;
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)) {
    days.add(day);
  }
  return days;
}

/// Which month the grid is showing. Kept out of the screen so paging back and
/// forth survives a rebuild.
class CalendarMonth extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void next() => state = DateTime(state.year, state.month + 1);
  void previous() => state = DateTime(state.year, state.month - 1);
}

final calendarMonthProvider =
    NotifierProvider<CalendarMonth, DateTime>(CalendarMonth.new);

final calendarSelectedDayProvider =
    NotifierProvider<CalendarSelectedDay, DateTime>(CalendarSelectedDay.new);

class CalendarSelectedDay extends Notifier<DateTime> {
  @override
  DateTime build() => startOfDay(DateTime.now());

  void select(DateTime day) => state = startOfDay(day);
}
