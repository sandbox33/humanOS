/// Habits and the three streak tiers (ported from v1's habits engine).
///
/// * per-habit streak — each habit against its own target;
/// * global streak — weighted day score ≥ 70 %;
/// * minimum streak — only the essential actions (2 of 3 by default): it
///   survives secondary failures, which is the point of having it.
///
/// A day without any record is *empty*, never a failure: it stops the count
/// but is not counted as a failed day. Today without records is *pending*
/// and does not break anything yet. Every 14 completed days earn a repair
/// token that bridges one failed or empty day. Breaking a streak keeps
/// `best`, and the UI shows "mejor racha" and "días cumplidos en 30"
/// instead of a red zero.
library;

import 'assumptions.dart';
import 'day.dart';

enum HabitMetric {
  check('check'),
  atLeast('min'),
  atMost('max');

  const HabitMetric(this.code);
  final String code;

  static HabitMetric parse(String? code) => HabitMetric.values.firstWhere(
    (m) => m.code == code,
    orElse: () => HabitMetric.check,
  );
}

class HabitDef {
  const HabitDef({
    required this.id,
    required this.alias,
    required this.weight,
    required this.isMinimum,
    this.metric = HabitMetric.check,
    this.target,
  });

  final int id;
  final String alias;
  final double weight;

  /// Essential action counted by the minimum streak.
  final bool isMinimum;
  final HabitMetric metric;
  final double? target;
}

class StreakParams {
  const StreakParams({
    required this.globalThreshold,
    required this.minimumRequired,
    required this.repairEveryDays,
    required this.maxToleranceFrac,
  });

  factory StreakParams.fromAssumptions(Assumptions a) => StreakParams(
    globalThreshold: a[A.globalStreakThreshold],
    minimumRequired: a.integer(A.minimumRequiredEssentials),
    repairEveryDays: a.integer(A.repairTokenEveryDays),
    maxToleranceFrac: a[A.habitMaxToleranceFrac],
  );

  final double globalThreshold;
  final int minimumRequired;
  final int repairEveryDays;
  final double maxToleranceFrac;
}

class HabitEval {
  const HabitEval({
    required this.fulfillment,
    required this.completed,
    required this.noData,
  });

  /// 0–1. Doing more than the target never compensates another habit.
  final double fulfillment;
  final bool completed;
  final bool noData;
}

/// Evaluates one habit for one day. [value] null means "not recorded".
HabitEval evaluateHabit(HabitDef habit, double? value, StreakParams params) {
  if (value == null) {
    return const HabitEval(fulfillment: 0, completed: false, noData: true);
  }
  switch (habit.metric) {
    case HabitMetric.check:
      final done = value > 0;
      return HabitEval(
        fulfillment: done ? 1 : 0,
        completed: done,
        noData: false,
      );
    case HabitMetric.atLeast:
      final target = habit.target ?? 1;
      if (target <= 0) {
        return const HabitEval(fulfillment: 1, completed: true, noData: false);
      }
      final f = value / target;
      return HabitEval(
        fulfillment: f > 1 ? 1 : (f < 0 ? 0 : f),
        completed: value >= target,
        noData: false,
      );
    case HabitMetric.atMost:
      final target = habit.target ?? 0;
      if (value <= target) {
        return const HabitEval(fulfillment: 1, completed: true, noData: false);
      }
      final tolerance = target * params.maxToleranceFrac;
      final f = tolerance > 0 ? 1 - (value - target) / tolerance : 0.0;
      return HabitEval(
        fulfillment: f < 0 ? 0 : f,
        completed: false,
        noData: false,
      );
  }
}

class DayScore {
  const DayScore({
    required this.points,
    required this.possible,
    required this.noData,
  });

  final double points;
  final double possible;
  final bool noData;

  double get fraction => possible == 0 ? 0 : points / possible;
}

/// Weighted score of a day. [values] maps habit id → value (absent = not
/// recorded).
DayScore scoreDay(
  List<HabitDef> habits,
  Map<int, double?> values,
  StreakParams params,
) {
  var points = 0.0;
  var possible = 0.0;
  var anyRecord = false;
  for (final h in habits) {
    possible += h.weight;
    final value = values[h.id];
    if (value != null) anyRecord = true;
    points += h.weight * evaluateHabit(h, value, params).fulfillment;
  }
  return DayScore(points: points, possible: possible, noData: !anyRecord);
}

class MinimumDay {
  const MinimumDay({
    required this.essentials,
    required this.done,
    required this.required,
    required this.noData,
  });

  final int essentials;
  final int done;
  final int required;
  final bool noData;

  bool get met => essentials > 0 && done >= required;
}

/// Minimum day: at least `minimumRequired` essentials completed (or all of
/// them when there are fewer).
MinimumDay minimumDay(
  List<HabitDef> habits,
  Map<int, double?> values,
  StreakParams params,
) {
  final essentials = habits.where((h) => h.isMinimum).toList();
  var done = 0;
  var anyRecord = false;
  for (final h in essentials) {
    final value = values[h.id];
    if (value != null) anyRecord = true;
    if (evaluateHabit(h, value, params).completed) done++;
  }
  final required = essentials.length < params.minimumRequired
      ? essentials.length
      : params.minimumRequired;
  return MinimumDay(
    essentials: essentials.length,
    done: done,
    required: required,
    noData: !anyRecord,
  );
}

enum DayStatus { completed, failed, empty, pending }

/// Streak tier being computed.
enum StreakKind {
  minimum('MINIMA'),
  global('GLOBAL');

  const StreakKind(this.code);
  final String code;
}

/// Status of every day for one tier. [valuesByDay] maps day → habit values.
Map<DateTime, DayStatus> dayStatuses({
  required StreakKind kind,
  required List<HabitDef> habits,
  required Map<DateTime, Map<int, double?>> valuesByDay,
  required DateTime today,
  required StreakParams params,
}) {
  final result = <DateTime, DayStatus>{};
  final todayDay = dateOnly(today);
  for (final entry in valuesByDay.entries) {
    final day = dateOnly(entry.key);
    if (day.isAfter(todayDay)) continue;
    final bool noData;
    final bool done;
    if (kind == StreakKind.minimum) {
      final m = minimumDay(habits, entry.value, params);
      noData = m.noData;
      done = m.met;
    } else {
      final s = scoreDay(habits, entry.value, params);
      noData = s.noData;
      done = !s.noData && s.fraction >= params.globalThreshold;
    }
    if (noData) {
      result[day] = day == todayDay ? DayStatus.pending : DayStatus.empty;
    } else {
      result[day] = done ? DayStatus.completed : DayStatus.failed;
    }
  }
  return result;
}

/// Status of every day for one habit.
Map<DateTime, DayStatus> habitStatuses({
  required HabitDef habit,
  required Map<DateTime, double?> values,
  required DateTime today,
  required StreakParams params,
}) {
  final todayDay = dateOnly(today);
  return {
    for (final e in values.entries)
      if (!dateOnly(e.key).isAfter(todayDay))
        dateOnly(e.key): e.value == null
            ? (dateOnly(e.key) == todayDay
                  ? DayStatus.pending
                  : DayStatus.empty)
            : (evaluateHabit(habit, e.value, params).completed
                  ? DayStatus.completed
                  : DayStatus.failed),
  };
}

class StreakSummary {
  const StreakSummary({
    required this.current,
    required this.best,
    required this.repairTokens,
    required this.repairsUsed,
    required this.completedLast30,
    required this.daysWithDataLast30,
  });

  final int current;
  final int best;
  final int repairTokens;
  final int repairsUsed;
  final int completedLast30;
  final int daysWithDataLast30;

  bool get broken => current == 0;
}

/// Walks every day from the first status to [today] in order. Days missing
/// from [statuses] are empty.
StreakSummary computeStreak(
  Map<DateTime, DayStatus> statuses, {
  required DateTime today,
  required StreakParams params,
}) {
  final todayDay = dateOnly(today);
  final normalized = {
    for (final e in statuses.entries) dateOnly(e.key): e.value,
  };
  if (normalized.isEmpty) {
    return const StreakSummary(
      current: 0,
      best: 0,
      repairTokens: 0,
      repairsUsed: 0,
      completedLast30: 0,
      daysWithDataLast30: 0,
    );
  }
  final first = normalized.keys.reduce((a, b) => a.isBefore(b) ? a : b);
  var current = 0, best = 0, tokens = 0, used = 0, completedTotal = 0;
  var completed30 = 0, withData30 = 0;
  final windowStart = addDays(todayDay, -29);
  for (var day = first; !day.isAfter(todayDay); day = addDays(day, 1)) {
    final status =
        normalized[day] ??
        (day == todayDay ? DayStatus.pending : DayStatus.empty);
    final inWindow = !day.isBefore(windowStart);
    switch (status) {
      case DayStatus.completed:
        current++;
        completedTotal++;
        if (params.repairEveryDays > 0 &&
            completedTotal % params.repairEveryDays == 0) {
          tokens++;
        }
        if (current > best) best = current;
        if (inWindow) {
          completed30++;
          withData30++;
        }
      case DayStatus.failed:
      case DayStatus.empty:
        if (status == DayStatus.failed && inWindow) withData30++;
        if (current > 0 && tokens > 0) {
          tokens--;
          used++;
        } else {
          current = 0;
        }
      case DayStatus.pending:
        break;
    }
  }
  return StreakSummary(
    current: current,
    best: best,
    repairTokens: tokens,
    repairsUsed: used,
    completedLast30: completed30,
    daysWithDataLast30: withData30,
  );
}

/// v1 re-entry ramp: two consecutive days failing the minimum *with data*
/// suggest a short action instead of showing a failure counter.
bool suggestMinimumMission(DayStatus? yesterday, DayStatus? today) =>
    yesterday == DayStatus.failed && today == DayStatus.failed;
