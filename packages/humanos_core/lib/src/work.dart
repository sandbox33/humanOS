/// Flexible work: entries with or without times, rates in cents per hour,
/// totals per day / ISO week / month and an optional overtime threshold.
///
/// * Time is integer minutes; money is integer cents.
/// * A shift that ends at or before its start time ended the next day.
/// * An entry with a rate and minutes earns `minutes × rate / 60` cents,
///   rounded half away from zero. With only a total, the total is kept and
///   the rate stays null. A rate without hours earns nothing known (null):
///   unknown is not zero.
/// * Minutes count on the entry's date (the day it started).
library;

import 'day.dart';
import 'money.dart';

enum WorkKind {
  estable('estable', 'Estable'),
  eventual('eventual', 'Eventual');

  const WorkKind(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static WorkKind parse(String? code) => WorkKind.values.firstWhere(
    (k) => k.code == code,
    orElse: () => WorkKind.eventual,
  );
}

/// One logged piece of work.
class WorkEntry {
  const WorkEntry({
    required this.date,
    required this.label,
    required this.kind,
    required this.minutes,
    this.id,
    this.start,
    this.end,
    this.rateCentsPerHour,
    this.earnedCents,
    this.note,
  });

  final int? id;

  /// Local calendar day the work started.
  final DateTime date;
  final String label;
  final WorkKind kind;

  /// Local wall-clock start and end; [end] may fall on the next day.
  final DateTime? start;
  final DateTime? end;
  final int minutes;
  final int? rateCentsPerHour;

  /// Null when unknown (never assumed to be zero).
  final int? earnedCents;
  final String? note;

  /// Started and not finished.
  bool get inProgress => start != null && end == null;

  /// Effective cents per hour, when both money and time are known.
  int? get effectiveRateCentsPerHour {
    final earned = earnedCents;
    if (earned == null || minutes <= 0) return null;
    return divRound(earned * 60, minutes);
  }
}

/// Minutes between two clock times on [day], crossing midnight when the
/// end is at or before the start (22:00 → 06:00 = 480 min).
({DateTime start, DateTime end, int minutes}) spanFromClock(
  DateTime day,
  int startMinuteOfDay,
  int endMinuteOfDay,
) {
  final base = DateTime(day.year, day.month, day.day);
  final start = base.add(Duration(minutes: startMinuteOfDay));
  var end = base.add(Duration(minutes: endMinuteOfDay));
  if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
  return (start: start, end: end, minutes: end.difference(start).inMinutes);
}

/// Minutes between two instants (0 when [end] is not after [start]).
int minutesBetween(DateTime start, DateTime end) =>
    end.isAfter(start) ? end.difference(start).inMinutes : 0;

/// Cents for [minutes] at [rateCentsPerHour], rounded half away from zero.
int earnedFor(int minutes, int rateCentsPerHour) {
  if (minutes < 0 || rateCentsPerHour < 0) {
    throw ArgumentError('minutos y tarifa no pueden ser negativos');
  }
  return divRound(minutes * rateCentsPerHour, 60);
}

/// Problems found when building an entry; empty means valid.
enum WorkIssue {
  noLabel('Ponle un nombre al trabajo.'),
  noTime('Faltan las horas: escribe inicio y fin o la duración.'),
  negative('Las horas y el dinero no pueden ser negativos.'),
  rateWithoutHours('Hay tarifa pero no horas: no se puede calcular lo ganado.');

  const WorkIssue(this.messageEs);
  final String messageEs;
}

/// Builds an entry from the quick form: template values, then whatever the
/// user typed. [startMin]/[endMin] (minutes of day) win over [minutes].
/// [totalCents] (only the total earned) wins over the rate.
({WorkEntry? entry, List<WorkIssue> issues}) buildWorkEntry({
  required DateTime date,
  required String label,
  required WorkKind kind,
  int? startMin,
  int? endMin,
  int? minutes,
  int? rateCentsPerHour,
  int? totalCents,
  String? note,
}) {
  final issues = <WorkIssue>[];
  if (label.trim().isEmpty) issues.add(WorkIssue.noLabel);
  if ((minutes ?? 0) < 0 ||
      (rateCentsPerHour ?? 0) < 0 ||
      (totalCents ?? 0) < 0) {
    issues.add(WorkIssue.negative);
  }
  DateTime? start, end;
  var mins = minutes ?? 0;
  if (startMin != null && endMin != null) {
    final span = spanFromClock(date, startMin, endMin);
    start = span.start;
    end = span.end;
    mins = span.minutes;
  } else if (startMin != null) {
    // Started now, not finished: no minutes yet.
    start = DateTime(
      date.year,
      date.month,
      date.day,
    ).add(Duration(minutes: startMin));
  }
  final finished = !(start != null && end == null);
  if (finished && mins <= 0 && totalCents == null) {
    issues.add(
      rateCentsPerHour != null ? WorkIssue.rateWithoutHours : WorkIssue.noTime,
    );
  }
  if (issues.isNotEmpty) return (entry: null, issues: issues);
  int? earned;
  int? rate = rateCentsPerHour;
  if (totalCents != null) {
    earned = totalCents;
    rate = null;
  } else if (rate != null && mins > 0) {
    earned = earnedFor(mins, rate);
  }
  return (
    entry: WorkEntry(
      date: dateOnly(date),
      label: label.trim(),
      kind: kind,
      start: start,
      end: end,
      minutes: mins,
      rateCentsPerHour: rate,
      earnedCents: earned,
      note: note,
    ),
    issues: const <WorkIssue>[],
  );
}

/// Closes an entry in progress at [now].
WorkEntry finishWork(WorkEntry entry, DateTime now) {
  final start = entry.start;
  if (start == null || entry.end != null) return entry;
  final mins = minutesBetween(start, now);
  final rate = entry.rateCentsPerHour;
  return WorkEntry(
    id: entry.id,
    date: entry.date,
    label: entry.label,
    kind: entry.kind,
    start: start,
    end: now,
    minutes: mins,
    rateCentsPerHour: rate,
    earnedCents:
        entry.earnedCents ??
        (rate != null && mins > 0 ? earnedFor(mins, rate) : null),
    note: entry.note,
  );
}

/// Minutes of [entry] per calendar day it touches (for charts); entries
/// without times keep all minutes on their date.
Map<DateTime, int> minutesByCalendarDay(WorkEntry entry) {
  final start = entry.start, end = entry.end;
  if (start == null || end == null) {
    return {dateOnly(entry.date): entry.minutes};
  }
  final result = <DateTime, int>{};
  var cursor = start;
  while (cursor.isBefore(end)) {
    final nextMidnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
    final stop = nextMidnight.isBefore(end) ? nextMidnight : end;
    final day = dateOnly(cursor);
    result[day] = (result[day] ?? 0) + stop.difference(cursor).inMinutes;
    cursor = stop;
  }
  return result;
}

/// Sum of a group of entries.
class WorkTotals {
  const WorkTotals({
    required this.entries,
    required this.minutes,
    required this.earnedCents,
    required this.unknownEarnings,
    required this.paidMinutes,
    this.overtimeMinutes,
  });

  final int entries;
  final int minutes;

  /// Sum of the known earnings only.
  final int earnedCents;

  /// Entries whose earnings are unknown.
  final int unknownEarnings;

  /// Minutes of the entries with known earnings (for the hourly value).
  final int paidMinutes;

  /// Minutes above the threshold; null when no threshold is set.
  final int? overtimeMinutes;

  /// Real income per hour over the entries that have both money and time.
  int? get centsPerHour =>
      paidMinutes <= 0 ? null : divRound(earnedCents * 60, paidMinutes);
}

WorkTotals sumWork(Iterable<WorkEntry> entries, {int? overtimeThresholdMin}) {
  var count = 0, minutes = 0, earned = 0, unknown = 0, paid = 0;
  for (final e in entries) {
    count++;
    minutes += e.minutes;
    final money = e.earnedCents;
    if (money == null) {
      unknown++;
    } else {
      earned += money;
      paid += e.minutes;
    }
  }
  final threshold = overtimeThresholdMin;
  return WorkTotals(
    entries: count,
    minutes: minutes,
    earnedCents: earned,
    unknownEarnings: unknown,
    paidMinutes: paid,
    overtimeMinutes: threshold == null
        ? null
        : (minutes > threshold ? minutes - threshold : 0),
  );
}

/// Monday of the ISO week of [day].
DateTime weekStart(DateTime day) {
  final d = dateOnly(day);
  return addDays(d, -(d.weekday - DateTime.monday));
}

/// Totals for the day, ISO week and month of [today]. Thresholds are
/// optional user settings (no default overtime rule).
({WorkTotals day, WorkTotals week, WorkTotals month}) workSummary(
  List<WorkEntry> entries, {
  required DateTime today,
  int? dailyOvertimeMin,
  int? weeklyOvertimeMin,
}) {
  final day = dateOnly(today);
  final monday = weekStart(day);
  final sunday = addDays(monday, 6);
  bool inWeek(DateTime d) =>
      !dateOnly(d).isBefore(monday) && !dateOnly(d).isAfter(sunday);
  bool inMonth(DateTime d) => d.year == day.year && d.month == day.month;
  return (
    day: sumWork(
      entries.where((e) => dateOnly(e.date) == day),
      overtimeThresholdMin: dailyOvertimeMin,
    ),
    week: sumWork(
      entries.where((e) => inWeek(e.date)),
      overtimeThresholdMin: weeklyOvertimeMin,
    ),
    month: sumWork(entries.where((e) => inMonth(e.date))),
  );
}

/// "7 h 30 min" for integer minutes.
String formatWorkMinutes(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h $m min';
}

/// Hours of work a purchase costs at the user's real hourly value.
String hoursOfWorkEs(int priceCents, int centsPerHour) {
  if (centsPerHour <= 0) return 'sin dato';
  return formatWorkMinutes(divRound(priceCents * 60, centsPerHour));
}

/// Schedule of a user work template (every field is user data; nothing is
/// assumed). Days use a bit mask: bit 0 Monday … bit 6 Sunday.
class WorkSchedule {
  const WorkSchedule({
    required this.label,
    this.startMin,
    this.endMin,
    this.breakStartMin,
    this.breakMinutes,
    this.daysMask,
    this.heatExposure = false,
  });

  final String label;
  final int? startMin;
  final int? endMin;
  final int? breakStartMin;
  final int? breakMinutes;
  final int? daysMask;
  final bool heatExposure;

  bool get hasTimes => startMin != null && endMin != null;

  /// Planned for [day]: has times and the weekday is in the mask.
  bool plannedOn(DateTime day) {
    final mask = daysMask;
    if (!hasTimes || mask == null) return false;
    return (mask >> (day.weekday - 1)) & 1 == 1;
  }

  /// Paid minutes of one planned day (span minus the break).
  int? plannedMinutes(DateTime day) {
    if (!hasTimes) return null;
    final span = spanFromClock(day, startMin!, endMin!).minutes;
    final pause = breakMinutes ?? 0;
    return span > pause ? span - pause : 0;
  }
}

int daysMaskOf(Iterable<int> weekdays) {
  var mask = 0;
  for (final d in weekdays) {
    if (d >= DateTime.monday && d <= DateTime.sunday) mask |= 1 << (d - 1);
  }
  return mask;
}

List<int> weekdaysOf(int? mask) => [
  if (mask != null)
    for (var d = DateTime.monday; d <= DateTime.sunday; d++)
      if ((mask >> (d - 1)) & 1 == 1) d,
];

/// A period of work during which notifications stay silent, except in the
/// break.
class WorkWindow {
  const WorkWindow({
    required this.start,
    required this.end,
    required this.label,
    this.breakStart,
    this.breakEnd,
    this.heatExposure = false,
  });

  final DateTime start;
  final DateTime end;
  final String label;
  final DateTime? breakStart;
  final DateTime? breakEnd;
  final bool heatExposure;

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  bool inBreak(DateTime t) {
    final b0 = breakStart, b1 = breakEnd;
    return b0 != null && b1 != null && !t.isBefore(b0) && t.isBefore(b1);
  }

  /// Inside the window and not in its break.
  bool silences(DateTime t) => contains(t) && !inBreak(t);
}

WorkWindow? _windowFor(DateTime day, WorkSchedule s) {
  if (!s.plannedOn(day)) return null;
  final span = spanFromClock(day, s.startMin!, s.endMin!);
  DateTime? b0, b1;
  final bs = s.breakStartMin, bm = s.breakMinutes;
  if (bs != null && bm != null && bm > 0) {
    var start = DateTime(
      day.year,
      day.month,
      day.day,
    ).add(Duration(minutes: bs));
    if (start.isBefore(span.start)) start = start.add(const Duration(days: 1));
    if (start.isBefore(span.end)) {
      b0 = start;
      b1 = start.add(Duration(minutes: bm));
    }
  }
  return WorkWindow(
    start: span.start,
    end: span.end,
    label: s.label,
    breakStart: b0,
    breakEnd: b1,
    heatExposure: s.heatExposure,
  );
}

/// Planned windows that touch [day]: those starting that day and those
/// started the day before that end after its midnight (night work).
List<WorkWindow> plannedWindows(
  DateTime day,
  Iterable<WorkSchedule> schedules,
) {
  final today = DateTime(day.year, day.month, day.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final result = <WorkWindow>[];
  for (final s in schedules) {
    final w = _windowFor(today, s);
    if (w != null) result.add(w);
    final prev = _windowFor(yesterday, s);
    if (prev != null && prev.end.isAfter(today)) result.add(prev);
  }
  result.sort((a, b) => a.start.compareTo(b.start));
  return result;
}

/// Window of an entry still in progress: until its template's end when the
/// template has times, otherwise for [openHours].
WorkWindow? inProgressWindow(
  WorkEntry entry, {
  required int openHours,
  WorkSchedule? schedule,
}) {
  final start = entry.start;
  if (start == null || entry.end != null) return null;
  var end = start.add(Duration(hours: openHours));
  if (schedule != null && schedule.hasTimes) {
    final planned = spanFromClock(
      entry.date,
      schedule.startMin!,
      schedule.endMin!,
    );
    if (planned.end.isAfter(start)) end = planned.end;
  }
  return WorkWindow(
    start: start,
    end: end,
    label: entry.label,
    heatExposure: schedule?.heatExposure ?? false,
  );
}
