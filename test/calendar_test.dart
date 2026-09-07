import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/domain/maintenance_record.dart';
import 'package:technician_portal/state/calendar_controller.dart';

MaintenanceRecord _record(String id, DateTime? due) =>
    MaintenanceRecord.fromJson({
      'id': id,
      'workOrderId': id,
      'dueDate': due?.toIso8601String(),
    });

void main() {
  group('month grid', () {
    test('starts on the Sunday before the first of the month', () {
      // 1 September 2026 is a Tuesday, so the grid opens on Sunday the 30th.
      final days = monthGrid(DateTime(2026, 9));

      expect(days.first, DateTime(2026, 8, 30));
      expect(days.first.weekday % 7, 0);
    });

    test('ends on the Saturday after the last of the month', () {
      // 30 September 2026 is a Wednesday, so it runs on to Saturday the 3rd.
      final days = monthGrid(DateTime(2026, 9));

      expect(days.last, DateTime(2026, 10, 3));
      expect(days.length % 7, 0);
    });

    test('a month that already starts on a Sunday gains no leading week', () {
      // 1 February 2026 is a Sunday.
      final days = monthGrid(DateTime(2026, 2));

      expect(days.first, DateTime(2026, 2));
    });

    test('handles a February that ends on a Saturday', () {
      final days = monthGrid(DateTime(2026, 2));

      expect(days.last, DateTime(2026, 2, 28));
      expect(days.length, 28);
    });
  });

  group('bucketing', () {
    test('groups by calendar day and orders each day by time', () {
      final late = _record('wo-late', DateTime(2026, 9, 4, 16));
      final early = _record('wo-early', DateTime(2026, 9, 4, 8));
      final other = _record('wo-other', DateTime(2026, 9, 5, 9));

      final buckets = bucketByDay([late, early, other]);

      expect(buckets.keys.toSet(), {'2026-09-04', '2026-09-05'});
      expect(
        buckets['2026-09-04']!.map((r) => r.id).toList(),
        ['wo-early', 'wo-late'],
      );
    });

    test('a record with no date is left out rather than bucketed as today', () {
      expect(bucketByDay([_record('wo-1', null)]), isEmpty);
    });
  });
}
