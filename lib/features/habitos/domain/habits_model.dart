import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/nutrients.dart';
import '../../../data/seed.dart';
import '../../../data/user_db.dart';
import '../../estado/domain/readiness_today.dart';
import '../../estado/domain/targets.dart';
import '../../heavy_duty/domain/training_plan.dart';
import '../../registro/domain/intake.dart';
import '../../turno/domain/hydration.dart';
import '../data/habits_repository.dart';

final habitsRepositoryProvider =
    Provider<HabitsRepository>((ref) => HabitsRepository(ref.watch(userDbProvider)));

final habitRowsProvider = StreamProvider<List<HabitRow>>(
  (ref) => ref.watch(habitsRepositoryProvider).watchHabits(),
);

final habitLogsProvider = StreamProvider<List<HabitLogRow>>(
  (ref) => ref.watch(habitsRepositoryProvider).watchLogs(),
);

final attributeRowsProvider = StreamProvider<List<AttributeRow>>(
  (ref) => ref.watch(habitsRepositoryProvider).watchAttributes(),
);

HabitDef habitDef(HabitRow r) => HabitDef(
      id: r.id,
      alias: r.alias,
      weight: r.weight,
      isMinimum: r.isMinimum,
      metric: HabitMetric.parse(r.metric),
      target: r.target,
    );

class HabitsOverview {
  const HabitsOverview({
    required this.habits,
    required this.today,
    required this.minimum,
    required this.global,
    required this.perHabit,
    required this.minimumToday,
    required this.scoreToday,
    required this.suggestMission,
  });

  final List<HabitRow> habits;
  final Map<int, double?> today;
  final StreakSummary minimum;
  final StreakSummary global;
  final Map<int, StreakSummary> perHabit;
  final MinimumDay minimumToday;
  final DayScore scoreToday;
  final bool suggestMission;
}

final habitsOverviewProvider = Provider<HabitsOverview?>((ref) {
  final rows = ref.watch(habitRowsProvider).value;
  final logs = ref.watch(habitLogsProvider).value;
  if (rows == null || logs == null) return null;
  final params = StreakParams.fromAssumptions(ref.watch(currentAssumptionsProvider));
  final today = ref.watch(todayProvider);
  final active = rows.where((r) => r.active).toList();
  final defs = [for (final r in active) habitDef(r)];
  final byDay = <DateTime, Map<int, double?>>{};
  for (final log in logs) {
    (byDay[parseIsoDate(log.date)] ??= {})[log.habitId] = log.value;
  }
  byDay.putIfAbsent(today, () => {});

  final minimumStatuses = dayStatuses(
      kind: StreakKind.minimum, habits: defs, valuesByDay: byDay, today: today, params: params);
  final globalStatuses = dayStatuses(
      kind: StreakKind.global, habits: defs, valuesByDay: byDay, today: today, params: params);
  final perHabit = <int, StreakSummary>{
    for (final h in defs)
      h.id: computeStreak(
        habitStatuses(
          habit: h,
          values: {for (final e in byDay.entries) e.key: e.value[h.id]},
          today: today,
          params: params,
        ),
        today: today,
        params: params,
      ),
  };
  final todayValues = byDay[today] ?? const {};
  return HabitsOverview(
    habits: active,
    today: todayValues,
    minimum: computeStreak(minimumStatuses, today: today, params: params),
    global: computeStreak(globalStatuses, today: today, params: params),
    perHabit: perHabit,
    minimumToday: minimumDay(defs, todayValues, params),
    scoreToday: scoreDay(defs, todayValues, params),
    suggestMission: suggestMinimumMission(
      minimumStatuses[addDays(today, -2)],
      minimumStatuses[addDays(today, -1)],
    ),
  );
});

/// Habit sources the app fills by itself (B3 is a manual check).
const autoHabitSources = {
  HabitSource.proteinG,
  HabitSource.weighIn,
  HabitSource.sober,
  HabitSource.screenMinutes,
  HabitSource.hydrationPct,
  HabitSource.sleepHours,
};

/// Automatic sources that may also be typed by hand when the band has no
/// data (an unknown automatic value never erases a manual one).
const manualFallbackSources = {HabitSource.sleepHours};

/// Today's value of every automatic source (null = unknown).
final autoHabitValuesProvider = Provider<Map<String, double?>>((ref) {
  final todayDay = ref.watch(todayProvider);
  final today = isoDate(todayDay);
  final intake = ref.watch(dayIntakeProvider(today)).value;
  final log = ref.watch(todayLogProvider);
  final weight = ref.watch(latestWeightProvider);
  final compliance = ref.watch(hydrationComplianceProvider);
  final sleepMin = ref.watch(dailyTelemetryProvider)[todayDay]?.sleepMinutes;
  final sober = log?.sober;
  return {
    HabitSource.proteinG: intake == null || intake.isEmpty
        ? null
        : intake.totals.value(NutrientKey.protein),
    HabitSource.weighIn: weight?.date == today ? 1 : 0,
    HabitSource.sober: sober == null ? null : (sober ? 1 : 0),
    HabitSource.screenMinutes: log?.screenMinutes?.toDouble(),
    HabitSource.hydrationPct:
        (log?.heatHours ?? 0) > 0 && compliance != null ? compliance * 100 : null,
    HabitSource.sleepHours: sleepMin == null ? null : sleepMin / 60,
  };
});

/// Mirrors today's automatic values into `habit_logs`. Manual habits are
/// never touched; an unknown source clears its value.
Future<void> syncAutoHabits(WidgetRef ref) async {
  final repo = ref.read(habitsRepositoryProvider);
  final values = ref.read(autoHabitValuesProvider);
  final today = isoDate(ref.read(todayProvider));
  for (final h in await repo.habits()) {
    final source = h.source;
    if (source == null || !autoHabitSources.contains(source)) continue;
    final value = values[source];
    if (value != null) {
      await repo.setValue(h.id, today, value);
    } else if (!manualFallbackSources.contains(source)) {
      await repo.clearValue(h.id, today);
    }
  }
}

final streakStateProvider = StreamProvider<List<StreakStateRow>>((ref) {
  final db = ref.watch(userDbProvider);
  return db.select(db.streakState).watch();
});

/// Stores the minimum and global streaks; returns the tiers whose current
/// count went up since the stored state (a real event for feedback).
Future<List<StreakKind>> saveStreaks(WidgetRef ref) async {
  final overview = ref.read(habitsOverviewProvider);
  if (overview == null) return const [];
  final stored = {
    for (final r in ref.read(streakStateProvider).value ?? const <StreakStateRow>[])
      r.kind: r,
  };
  final repo = ref.read(habitsRepositoryProvider);
  final up = <StreakKind>[];
  for (final (kind, summary) in [
    (StreakKind.minimum, overview.minimum),
    (StreakKind.global, overview.global),
  ]) {
    final previous = stored[kind.code];
    if (previous != null && summary.current > previous.current) up.add(kind);
    if (previous == null ||
        previous.current != summary.current ||
        previous.best != summary.best ||
        previous.repairTokens != summary.repairTokens) {
      await repo.saveStreak(
        kind.code,
        current: summary.current,
        best: summary.best,
        tokens: summary.repairTokens,
      );
    }
  }
  return up;
}

/// The four attributes from real data.
final attributesProvider = Provider<Map<AttributeKind, double?>>((ref) {
  final a = ref.watch(currentAssumptionsProvider);
  final params = AttributeParams.fromAssumptions(a);
  final today = ref.watch(todayProvider);
  final history = ref.watch(trainingHistoryProvider);
  final catalog = ref.watch(exerciseCatalogProvider);
  final bodyWeight = ref.watch(bodyWeightProvider);

  final baseline = <int, double>{};
  final current = <int, double>{};
  final sorted = [...history]..sort((x, y) => x.date.compareTo(y.date));
  for (final session in sorted) {
    for (final set in session.sets) {
      if (set.isWarmup) continue;
      final exercise = catalog[set.exerciseId];
      if (exercise == null || exercise.timed) continue;
      final load = effectiveLoad(exercise, set.loadKg, bodyWeight);
      final e1rm = load == null ? null : epleyE1rm(load, set.validReps);
      if (e1rm == null) continue;
      baseline.putIfAbsent(set.exerciseId, () => e1rm);
      if (e1rm > (current[set.exerciseId] ?? 0)) current[set.exerciseId] = e1rm;
    }
  }

  final logs = ref.watch(dailyLogsProvider).value ?? const <DailyLogRow>[];
  final sweat = SweatParams.fromAssumptions(a);
  final rate = ref.watch(latestSweatTestProvider)?.rate;
  final shifts = [
    for (final l in logs)
      if ((l.heatHours ?? 0) > 0)
        ShiftHydration(
          date: parseIsoDate(l.date),
          plannedL: plannedLitres(planFor(l.heatHours!, sweat, rate)),
          drankL: l.fluidsL,
        ),
  ];

  final telemetry = ref.watch(dailyTelemetryProvider);
  final sleep = <double>[
    for (var i = 0; i < 7; i++)
      if (telemetry[addDays(today, -i)]?.sleepMinutes != null)
        telemetry[addDays(today, -i)]!.sleepMinutes! / 60,
  ];
  final recovery = ref.watch(recoveryHistoryProvider);
  final recent = <double>[];
  final base = <double>[];
  for (final r in recovery) {
    final rhr = r.rhrBpm;
    if (rhr == null) continue;
    final age = daysBetween(r.date, today);
    if (age >= 0 && age < 7) recent.add(rhr);
    if (age >= 7 && age < 35) base.add(rhr);
  }
  double? mean(List<double> v) => v.isEmpty ? null : v.reduce((x, y) => x + y) / v.length;

  final overview = ref.watch(habitsOverviewProvider);
  final screenHabit = overview?.habits
      .where((h) => h.source == HabitSource.screenMinutes)
      .firstOrNull;
  final rows = ref.watch(habitRowsProvider).value ?? const <HabitRow>[];
  final logsByDay = <DateTime, Map<int, double?>>{};
  for (final l in ref.watch(habitLogsProvider).value ?? const <HabitLogRow>[]) {
    (logsByDay[parseIsoDate(l.date)] ??= {})[l.habitId] = l.value;
  }
  final streakParams = StreakParams.fromAssumptions(a);
  final defs = [for (final r in rows.where((r) => r.active)) habitDef(r)];
  final discipline = [
    for (final l in logs)
      DisciplineDay(
        date: parseIsoDate(l.date),
        sober: l.sober,
        screenMinutes: l.screenMinutes?.toDouble(),
        minimumMet: () {
          final values = logsByDay[parseIsoDate(l.date)];
          if (values == null) return null;
          final m = minimumDay(defs, values, streakParams);
          return m.noData ? null : m.met;
        }(),
      ),
  ];

  return computeAttributes(
    AttributeInputs(
      today: today,
      e1rmCurrent: current,
      e1rmBaseline: baseline,
      shifts: shifts,
      sleepHoursLast7: sleep,
      rhrRecentMean: mean(recent),
      rhrBaselineMean: mean(base),
      rhrBaselineSd: base.length >= 2 ? sampleSd(base) : null,
      disciplineDays: discipline,
      screenLimitMinutes: screenHabit?.target,
    ),
    params,
  );
});

/// Saves today's attributes and returns those that rose above the last
/// stored day for the first time today (the feedback event).
Future<List<AttributeKind>> saveAttributes(WidgetRef ref) async {
  final values = ref.read(attributesProvider);
  final today = isoDate(ref.read(todayProvider));
  final rows = ref.read(attributeRowsProvider).value ?? const <AttributeRow>[];
  final previous = <AttributeKind, double?>{};
  final storedToday = <AttributeKind, double>{};
  for (final row in rows) {
    for (final kind in AttributeKind.values) {
      if (kind.code != row.attr) continue;
      if (row.date == today) {
        storedToday[kind] = row.value;
      } else if (row.date.compareTo(today) < 0) {
        previous[kind] = row.value;
      }
    }
  }
  final repo = ref.read(habitsRepositoryProvider);
  for (final entry in values.entries) {
    final value = entry.value;
    if (value != null && storedToday[entry.key] != value) {
      await repo.saveAttribute(today, entry.key.code, value);
    }
  }
  return [
    for (final kind in attributesUp(previous, values))
      if (storedToday[kind] == null || values[kind]! > storedToday[kind]! + 1e-9) kind,
  ];
}
