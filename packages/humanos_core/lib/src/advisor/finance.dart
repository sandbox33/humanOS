/// Money flows and goals for the finance advisor (Fase 5). Integer cents
/// only; dates are calendar days. Nothing here is preloaded: categories,
/// goals and thresholds are user data.
library;

import '../day.dart';
import '../money.dart';
import '../work.dart';

/// Income of one day (from `work_entries` with known money).
class MoneyIn {
  const MoneyIn({required this.date, required this.cents});

  /// Income of the work entries that have money; entries without a rate
  /// or a total are unknown, not zero, and are left out.
  static List<MoneyIn> fromWork(Iterable<WorkEntry> entries) => [
    for (final e in entries)
      if (e.earnedCents case final cents?)
        MoneyIn(date: dateOnly(e.date), cents: cents),
  ];

  final DateTime date;
  final int cents;
}

/// One expense as the user logged it.
class Expense {
  const Expense({
    required this.date,
    required this.category,
    required this.amountCents,
    this.planned = false,
    this.impulse = false,
    this.note,
  });

  final DateTime date;
  final String category;
  final int amountCents;
  final bool planned;
  final bool impulse;
  final String? note;
}

/// Income and expenses of one ISO week.
class WeekFlow {
  const WeekFlow({
    required this.start,
    required this.incomeCents,
    required this.expenseCents,
    required this.plannedCents,
  });

  final DateTime start;
  final int incomeCents;
  final int expenseCents;

  /// Planned expenses: the user's basic spending.
  final int plannedCents;

  int get surplusCents => incomeCents - expenseCents;

  /// (income − expenses) / income; null when there was no income (a week
  /// without work has no rate, it is not 0 % nor −∞).
  double? get savingsRate =>
      incomeCents <= 0 ? null : surplusCents / incomeCents;
}

bool _inWeek(DateTime day, DateTime monday) {
  final d = dateOnly(day);
  return !d.isBefore(monday) && d.isBefore(addDays(monday, 7));
}

/// The [weeks] ISO weeks ending with the week of [today], oldest first.
List<WeekFlow> weeklyFlows({
  required List<MoneyIn> income,
  required List<Expense> expenses,
  required DateTime today,
  int weeks = 4,
}) {
  final current = weekStart(today);
  return [
    for (var i = weeks - 1; i >= 0; i--)
      () {
        final monday = addDays(current, -7 * i);
        var inCents = 0, outCents = 0, planned = 0;
        for (final m in income) {
          if (_inWeek(m.date, monday)) inCents += m.cents;
        }
        for (final e in expenses) {
          if (!_inWeek(e.date, monday)) continue;
          outCents += e.amountCents;
          if (e.planned) planned += e.amountCents;
        }
        return WeekFlow(
          start: monday,
          incomeCents: inCents,
          expenseCents: outCents,
          plannedCents: planned,
        );
      }(),
  ];
}

/// Average weekly surplus over [flows], rounded to cents.
int averageSurplusCents(List<WeekFlow> flows) => flows.isEmpty
    ? 0
    : divRound(flows.fold(0, (a, f) => a + f.surplusCents), flows.length);

enum Trend {
  sube('sube'),
  baja('baja'),
  estable('estable');

  const Trend(this.labelEs);
  final String labelEs;
}

/// Direction of the savings rate: the latest week with income against the
/// mean of the earlier ones. Null with fewer than two weeks with income.
/// [tolerance] is the change (as a fraction) still called "estable".
Trend? savingsTrend(List<WeekFlow> flows, {double tolerance = 0.02}) {
  final rates = [for (final f in flows) ?f.savingsRate];
  if (rates.length < 2) return null;
  final last = rates.last;
  final earlier = rates.sublist(0, rates.length - 1);
  final mean = earlier.reduce((a, b) => a + b) / earlier.length;
  if (last > mean + tolerance) return Trend.sube;
  if (last < mean - tolerance) return Trend.baja;
  return Trend.estable;
}

// ------------------------------------------------------------------ goals

enum GoalStatus {
  activo('activo', 'ACTIVO'),
  pausado('pausado', 'PAUSADO'),
  completado('completado', 'COMPLETADO'),
  descartado('descartado', 'DESCARTADO');

  const GoalStatus(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static GoalStatus parse(String? code) => GoalStatus.values.firstWhere(
    (s) => s.code == code,
    orElse: () => GoalStatus.activo,
  );
}

/// A user goal. A goal with children groups sub-goals and takes its
/// progress from them.
class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.priority,
    this.parentId,
    this.targetCents,
    this.savedCents = 0,
    this.status = GoalStatus.activo,
    this.actualCents,
  });

  final int id;
  final int? parentId;
  final String title;

  /// Unknown cost: no ETA can be computed.
  final int? targetCents;
  final int savedCents;

  /// Lower number first (the user's order).
  final int priority;
  final GoalStatus status;

  /// Real cost, recorded on completion.
  final int? actualCents;
}

/// Saved and target of [goal]: its own, or the sum of its non-discarded
/// children. The target is null when any counted child has no target.
({int savedCents, int? targetCents}) goalProgress(Goal goal, List<Goal> all) {
  final children = [
    for (final g in all)
      if (g.parentId == goal.id && g.status != GoalStatus.descartado) g,
  ];
  if (children.isEmpty) {
    return (savedCents: goal.savedCents, targetCents: goal.targetCents);
  }
  var saved = 0;
  int? target = 0;
  for (final c in children) {
    final p = goalProgress(c, all);
    saved += p.savedCents;
    target = (target == null || p.targetCents == null)
        ? null
        : target + p.targetCents!;
  }
  return (savedCents: saved, targetCents: target);
}

/// Missing cents of [goal] (never negative); null without a target.
int? goalRemainingCents(Goal goal, List<Goal> all) {
  final p = goalProgress(goal, all);
  final target = p.targetCents;
  if (target == null) return null;
  final left = target - p.savedCents;
  return left < 0 ? 0 : left;
}

/// Active goals in the user's order; ties keep the lower id first, so the
/// order never changes between two runs.
List<Goal> orderedActiveGoals(List<Goal> goals) {
  final active = [
    for (final g in goals)
      if (g.status == GoalStatus.activo) g,
  ];
  active.sort((a, b) {
    final byPriority = a.priority.compareTo(b.priority);
    return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
  });
  return active;
}

/// Weeks to reach [goal] at [weeklySurplusCents]; null when there is no
/// target or the surplus is not positive. Zero when already reached.
int? goalEtaWeeks(Goal goal, List<Goal> all, int weeklySurplusCents) {
  final left = goalRemainingCents(goal, all);
  if (left == null || weeklySurplusCents <= 0) return null;
  if (left == 0) return 0;
  return (left + weeklySurplusCents - 1) ~/ weeklySurplusCents;
}

/// Share of [incomeCents] to set aside at [percent] (whole percent),
/// rounded down to the cent: never more than was earned.
int splitCents(int incomeCents, int percent) {
  if (incomeCents <= 0 || percent <= 0) return 0;
  final p = percent > 100 ? 100 : percent;
  return incomeCents * p ~/ 100;
}
