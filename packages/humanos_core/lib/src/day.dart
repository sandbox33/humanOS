/// Calendar-day helpers shared by every engine.
///
/// The databases store dates as ISO `YYYY-MM-DD` text. Engines work with
/// [DateTime] values truncated to the day, built in UTC so that daylight
/// saving changes never make a "day" 23 or 25 hours long.
library;

/// Truncates [value] to its calendar day, expressed as a UTC midnight.
DateTime dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

/// Whole days from [from] to [to] (positive when [to] is later).
int daysBetween(DateTime from, DateTime to) =>
    dateOnly(to).difference(dateOnly(from)).inDays;

/// Adds [days] calendar days to [value]'s day.
DateTime addDays(DateTime value, int days) {
  final d = dateOnly(value);
  return DateTime.utc(d.year, d.month, d.day + days);
}

/// Formats a day as `YYYY-MM-DD`.
String isoDate(DateTime value) {
  final d = dateOnly(value);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-$mm-$dd';
}

/// Parses `YYYY-MM-DD` into a UTC midnight. Throws [FormatException] on
/// anything else.
DateTime parseIsoDate(String text) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
  if (match == null) {
    throw FormatException('Fecha inválida, se esperaba AAAA-MM-DD', text);
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  if (parsed.month != month || parsed.day != day) {
    throw FormatException('Fecha inexistente', text);
  }
  return parsed;
}

/// Minutes since midnight for a `HH:MM` string (24 h clock).
int parseClock(String text) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
  if (match == null) {
    throw FormatException('Hora inválida, se esperaba HH:MM', text);
  }
  final hours = int.parse(match.group(1)!);
  final minutes = int.parse(match.group(2)!);
  if (hours > 23 || minutes > 59) {
    throw FormatException('Hora fuera de rango', text);
  }
  return hours * 60 + minutes;
}

/// Formats minutes since midnight as `HH:MM`, wrapping past midnight.
String formatClock(int minuteOfDay) {
  final wrapped = ((minuteOfDay % 1440) + 1440) % 1440;
  final h = (wrapped ~/ 60).toString().padLeft(2, '0');
  final m = (wrapped % 60).toString().padLeft(2, '0');
  return '$h:$m';
}
