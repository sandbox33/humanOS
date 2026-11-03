/// Morning alarms created by the user: a clock time and the weekdays it
/// repeats on (bit 0 Monday … bit 6 Sunday). The phone schedules them as
/// exact alarm-clock alarms; this file only computes the next ring.
library;

import 'work.dart' show weekdaysOf;

/// Next ring strictly after [now] at [minuteOfDay] on a weekday of
/// [daysMask], in local wall-clock time. Null when no weekday is set.
DateTime? nextAlarmAt({
  required int minuteOfDay,
  required int daysMask,
  required DateTime now,
}) {
  if (minuteOfDay < 0 || minuteOfDay >= 24 * 60) {
    throw ArgumentError.value(minuteOfDay, 'minuteOfDay');
  }
  final days = weekdaysOf(daysMask).toSet();
  if (days.isEmpty) return null;
  for (var i = 0; i <= 7; i++) {
    // Calendar arithmetic, so a DST change never shifts the clock time.
    final candidate = DateTime(
      now.year,
      now.month,
      now.day + i,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );
    if (days.contains(candidate.weekday) && candidate.isAfter(now)) {
      return candidate;
    }
  }
  return null;
}

/// "en 7 h 30 min", "en 45 min", "en menos de 1 min".
String untilAlarmEs(DateTime next, DateTime now) {
  final minutes = next.difference(now).inMinutes;
  if (minutes < 1) return 'en menos de 1 min';
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return 'en $m min';
  return m == 0 ? 'en $h h' : 'en $h h $m min';
}
