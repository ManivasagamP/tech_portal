import 'package:intl/intl.dart';

final _shortDate = DateFormat('MMM d, yyyy');
final _shortDateTime = DateFormat('MMM d, yyyy h:mm a');
final _dayTime = DateFormat('h:mm a');
final _dayKey = DateFormat('yyyy-MM-dd');
final _monthTitle = DateFormat('MMMM yyyy');
final _fullDay = DateFormat('EEEE, MMMM d, yyyy');
final _sessionDate = DateFormat('dd/MM/yyyy');
final _sessionTime = DateFormat('HH:mm');

String formatDate(DateTime date) => _shortDate.format(date);
String formatDateTimeShort(DateTime date) => _shortDateTime.format(date);
String formatTimeOfDay(DateTime date) => _dayTime.format(date);
String formatDayKey(DateTime date) => _dayKey.format(date);
String formatMonthTitle(DateTime date) => _monthTitle.format(date);
String formatFullDay(DateTime date) => _fullDay.format(date);
String formatSessionDate(DateTime date) => _sessionDate.format(date);
String formatSessionTime(DateTime date) => _sessionTime.format(date);

/// Web renders today's timestamps as time-only, older ones with the date.
String formatHistoryTimestamp(DateTime date) =>
    isSameDay(date, DateTime.now()) ? formatTimeOfDay(date) : formatDateTimeShort(date);

DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Matches OrderCard: past date, and not today.
bool isOverdueDate(DateTime date) {
  final now = DateTime.now();
  return date.isBefore(now) && !isSameDay(date, now);
}

String formatMinutesAsHours(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  return '${h}h ${m}m';
}

String formatElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}
