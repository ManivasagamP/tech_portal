import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/utils/dates.dart';

void main() {
  test('isOverdueDate ignores earlier today', () {
    final earlierToday = DateTime.now().subtract(const Duration(hours: 2));
    expect(isOverdueDate(earlierToday), isFalse);
  });

  test('isOverdueDate flags a past calendar day', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    expect(isOverdueDate(yesterday), isTrue);
  });

  test('formatMinutesAsHours mirrors the checklist chip', () {
    expect(formatMinutesAsHours(0), '0m');
    expect(formatMinutesAsHours(45), '45m');
    expect(formatMinutesAsHours(90), '1h 30m');
  });

  test('formatElapsed renders the live work-order timer', () {
    expect(formatElapsed(const Duration(hours: 2, minutes: 5, seconds: 9)),
        '2:05:09');
  });

  test('formatDayKey is the calendar bucket key', () {
    expect(formatDayKey(DateTime(2026, 9, 3)), '2026-09-03');
  });
}
