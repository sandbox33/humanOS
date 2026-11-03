/// Screen time by app, category and schedule block (B2), computed from the
/// phone's usage events (app resumed / paused), the same source as the
/// system's digital-wellbeing screen. Every category and every hiding rule
/// is the user's.
library;

import 'day.dart';
import 'day_schedule.dart';

enum AppCategory {
  trabajo('trabajo', 'Trabajo / proyecto'),
  comunicacion('comunicacion', 'Comunicación'),
  ocio('ocio', 'Ocio'),
  redes('redes', 'Redes'),
  utilidades('utilidades', 'Utilidades'),
  sinClasificar('sin_clasificar', 'Sin clasificar');

  const AppCategory(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static AppCategory parse(String? code) => AppCategory.values.firstWhere(
    (c) => c.code == code,
    orElse: () => AppCategory.sinClasificar,
  );
}

/// The first suggestion for an app from the category its developer
/// declared to Android (`ApplicationInfo.category`); the user corrects it.
/// Undeclared or unknown → sin clasificar.
AppCategory suggestCategory(int? androidCategory) => switch (androidCategory) {
  0 => AppCategory.ocio, // CATEGORY_GAME
  1 => AppCategory.ocio, // CATEGORY_AUDIO
  2 => AppCategory.ocio, // CATEGORY_VIDEO
  3 => AppCategory.utilidades, // CATEGORY_IMAGE
  4 => AppCategory.redes, // CATEGORY_SOCIAL
  5 => AppCategory.utilidades, // CATEGORY_NEWS
  6 => AppCategory.utilidades, // CATEGORY_MAPS
  7 => AppCategory.trabajo, // CATEGORY_PRODUCTIVITY
  8 => AppCategory.utilidades, // CATEGORY_ACCESSIBILITY
  _ => AppCategory.sinClasificar,
};

enum UsageEventType { resumed, paused }

/// One usage event from the phone.
class UsageEvent {
  const UsageEvent({
    required this.package,
    required this.type,
    required this.at,
    this.activity = '',
  });

  final String package;

  /// Activities of one app are paired separately (one may pause after
  /// another of the same app resumed).
  final String activity;
  final UsageEventType type;
  final DateTime at;
}

/// A stretch of time one app was on screen.
class UsageInterval {
  const UsageInterval({
    required this.package,
    required this.start,
    required this.end,
  });

  final String package;
  final DateTime start;
  final DateTime end;

  int get seconds => end.difference(start).inSeconds;
}

/// Pairs resumed/paused events per app activity. An app still on screen
/// counts until [until]; a pause without its resume (before the window) is
/// ignored. Overlaps of the same app (two activities) are merged so time is
/// never counted twice.
List<UsageInterval> intervalsFromEvents(
  List<UsageEvent> events, {
  required DateTime until,
}) {
  final sorted = [...events]..sort((a, b) => a.at.compareTo(b.at));
  final open = <String, UsageEvent>{};
  final raw = <UsageInterval>[];
  for (final e in sorted) {
    final key = '${e.package}/${e.activity}';
    switch (e.type) {
      case UsageEventType.resumed:
        open.putIfAbsent(key, () => e);
      case UsageEventType.paused:
        final from = open.remove(key);
        if (from != null && e.at.isAfter(from.at)) {
          raw.add(UsageInterval(package: e.package, start: from.at, end: e.at));
        }
    }
  }
  for (final from in open.values) {
    if (until.isAfter(from.at)) {
      raw.add(UsageInterval(package: from.package, start: from.at, end: until));
    }
  }
  // Merge overlapping intervals of the same app.
  final byApp = <String, List<UsageInterval>>{};
  for (final i in raw) {
    (byApp[i.package] ??= []).add(i);
  }
  final out = <UsageInterval>[];
  for (final entry in byApp.entries) {
    final list = entry.value..sort((a, b) => a.start.compareTo(b.start));
    var current = list.first;
    for (final i in list.skip(1)) {
      if (!i.start.isAfter(current.end)) {
        current = UsageInterval(
          package: entry.key,
          start: current.start,
          end: i.end.isAfter(current.end) ? i.end : current.end,
        );
      } else {
        out.add(current);
        current = i;
      }
    }
    out.add(current);
  }
  return out..sort((a, b) => a.start.compareTo(b.start));
}

DateTime _max(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

/// Seconds of [intervals] inside [from, to).
int _secondsWithin(UsageInterval i, DateTime from, DateTime to) {
  final s = _max(i.start, from), e = _min(i.end, to);
  return e.isAfter(s) ? e.difference(s).inSeconds : 0;
}

int _minutes(int seconds) => (seconds + 30) ~/ 60;

/// Minutes per app on calendar [day] (time across midnight is split).
Map<String, int> minutesByApp(List<UsageInterval> intervals, DateTime day) {
  final from = dateOnly(day), to = addDays(dateOnly(day), 1);
  final seconds = <String, int>{};
  for (final i in intervals) {
    final s = _secondsWithin(i, from, to);
    if (s > 0) seconds[i.package] = (seconds[i.package] ?? 0) + s;
  }
  return {
    for (final e in seconds.entries)
      if (_minutes(e.value) > 0) e.key: _minutes(e.value),
  };
}

/// Minutes per category from minutes per app; apps the user did not
/// classify count as sin clasificar.
Map<AppCategory, int> minutesByCategory(
  Map<String, int> byApp,
  Map<String, AppCategory> classes,
) {
  final out = <AppCategory, int>{};
  for (final e in byApp.entries) {
    final c = classes[e.key] ?? AppCategory.sinClasificar;
    out[c] = (out[c] ?? 0) + e.value;
  }
  return out;
}

/// Minutes per category inside each active block of [plan] for [day].
/// Meals overlap work, so a minute can count in both a meal and the work
/// block around it.
Map<int, Map<AppCategory, int>> minutesByBlock({
  required List<UsageInterval> intervals,
  required List<PlannedBlock> plan,
  required DateTime day,
  required Map<String, AppCategory> classes,
}) {
  final base = dateOnly(day);
  final out = <int, Map<AppCategory, int>>{};
  for (final b in plan) {
    if (!b.active) continue;
    final from = base.add(Duration(minutes: b.startMin));
    final to = base.add(Duration(minutes: b.endMin));
    final seconds = <AppCategory, int>{};
    for (final i in intervals) {
      final s = _secondsWithin(i, from, to);
      if (s == 0) continue;
      final c = classes[i.package] ?? AppCategory.sinClasificar;
      seconds[c] = (seconds[c] ?? 0) + s;
    }
    final minutes = {
      for (final e in seconds.entries)
        if (_minutes(e.value) > 0) e.key: _minutes(e.value),
    };
    if (minutes.isNotEmpty) out[b.id] = minutes;
  }
  return out;
}

/// The user's rule: [categories] are hidden from the home screen while any
/// of [blockIds] is under way.
class HideRule {
  const HideRule({required this.blockIds, required this.categories});

  final Set<int> blockIds;
  final Set<AppCategory> categories;

  bool get isEmpty => blockIds.isEmpty || categories.isEmpty;
}

/// Categories hidden at [nowMin] (minutes from today's midnight). Every
/// active block that contains the moment counts, also yesterday's blocks
/// that run past midnight (sleep).
Set<AppCategory> hiddenCategoriesAt({
  required HideRule rule,
  required int nowMin,
  required List<PlannedBlock> today,
  List<PlannedBlock> yesterday = const [],
}) {
  if (rule.isEmpty) return const {};
  bool contains(PlannedBlock b, int shift) =>
      b.active &&
      rule.blockIds.contains(b.id) &&
      b.startMin + shift <= nowMin &&
      nowMin < b.endMin + shift;
  final inside =
      today.any((b) => contains(b, 0)) ||
      yesterday.any((b) => contains(b, -24 * 60));
  return inside ? rule.categories : const {};
}

/// Minutes of apps of the hidden categories used during the hidden blocks
/// of [day] (opened by another way): shown as data, never as a reproach.
int minutesWhileHidden({
  required List<UsageInterval> intervals,
  required List<PlannedBlock> plan,
  required DateTime day,
  required HideRule rule,
  required Map<String, AppCategory> classes,
}) {
  if (rule.isEmpty) return 0;
  final base = dateOnly(day);
  var seconds = 0;
  for (final b in plan) {
    if (!b.active || !rule.blockIds.contains(b.id)) continue;
    final from = base.add(Duration(minutes: b.startMin));
    final to = base.add(Duration(minutes: b.endMin));
    for (final i in intervals) {
      if (rule.categories.contains(
        classes[i.package] ?? AppCategory.sinClasificar,
      )) {
        seconds += _secondsWithin(i, from, to);
      }
    }
  }
  return _minutes(seconds);
}

/// Seven daily totals ending with [today] (oldest first); days without a
/// record are null, not zero.
List<int?> sevenDayTrend(Map<String, int> totalsByDate, DateTime today) => [
  for (var i = 6; i >= 0; i--) totalsByDate[isoDate(addDays(today, -i))],
];
