import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/nutrients.dart';
import '../../../data/settings.dart';
import '../../../data/user_db.dart';
import '../../registro/domain/intake.dart';
import '../../turno/data/daily_log_repository.dart';
import '../data/body_repository.dart';

final bodyRepositoryProvider =
    Provider<BodyRepository>((ref) => BodyRepository(ref.watch(userDbProvider)));

final dailyLogRepositoryProvider =
    Provider<DailyLogRepository>((ref) => DailyLogRepository(ref.watch(userDbProvider)));

final bodyMetricsProvider = StreamProvider<List<BodyMetricRow>>(
  (ref) => ref.watch(bodyRepositoryProvider).watchAll(),
);

/// Daily logs of the last 120 days (sweat tests, effort, fluids…).
final dailyLogsProvider = StreamProvider<List<DailyLogRow>>((ref) {
  final from = isoDate(addDays(ref.watch(todayProvider), -119));
  return ref.watch(dailyLogRepositoryProvider).watchSince(from);
});

final todayLogProvider = Provider<DailyLogRow?>((ref) {
  final today = isoDate(ref.watch(todayProvider));
  for (final log in ref.watch(dailyLogsProvider).value ?? const <DailyLogRow>[]) {
    if (log.date == today) return log;
  }
  return null;
});

/// kcal per day over the last 60 days; `partial` when an item had no
/// energy data (such days never count for the adaptive TDEE).
final intakeKcalHistoryProvider =
    StreamProvider<Map<String, ({double kcal, bool partial})>>((ref) {
  final today = ref.watch(todayProvider);
  final resolver = ref.watch(nutritionResolverProvider);
  return ref
      .watch(mealsRepositoryProvider)
      .watchItemsBetween(isoDate(addDays(today, -59)), isoDate(today))
      .map((byDay) => {
            for (final e in byDay.entries)
              e.key: () {
                final totals = NutrientTotals();
                for (final item in e.value) {
                  final food = resolver.resolve(
                      foodId: item.foodId, barcode: item.barcode, recipeId: item.recipeId);
                  totals.add(food.name, food.profile, item.grams);
                }
                return (
                  kcal: totals.value(NutrientKey.energy) ?? 0.0,
                  partial: totals.isPartial(NutrientKey.energy),
                );
              }(),
          });
});

/// Latest weigh-in, if any.
final latestWeightProvider = Provider<({String date, double kg})?>((ref) {
  final rows = ref.watch(bodyMetricsProvider).value ?? const <BodyMetricRow>[];
  for (final r in rows.reversed) {
    if (r.weightKg != null) return (date: r.date, kg: r.weightKg!);
  }
  return null;
});

class EnergyStatus {
  const EnergyStatus({
    required this.weightKg,
    required this.trend,
    required this.estimate,
    required this.adaptive,
    required this.targetKcal,
    required this.bmr,
    required this.dayEnergy,
    required this.macros,
    required this.modeEs,
  });

  final double weightKg;
  final List<TrendPoint> trend;
  final TdeeEstimate estimate;
  final bool adaptive;
  final double targetKcal;
  final double bmr;
  final DayEnergy dayEnergy;
  final MacroTargets macros;
  final String modeEs;

  double? get trendKg => trend.isEmpty ? null : trend.last.trendKg;
}

DayType dayTypeOf(DailyLogRow? log) {
  final effort = WorkEffort.parse(log?.workEffort);
  if (effort == null) return DayType.unknown;
  return effort == WorkEffort.off ? DayType.offDay : DayType.workday;
}

/// Today's energy and macro targets. Null until the first weigh-in.
final energyStatusProvider = Provider<EnergyStatus?>((ref) {
  final profile = ref.watch(profileProvider).value;
  final weight = ref.watch(latestWeightProvider);
  if (profile == null || weight == null) return null;
  final a = ref.watch(currentAssumptionsProvider);
  final today = ref.watch(todayProvider);
  final metrics = ref.watch(bodyMetricsProvider).value ?? const <BodyMetricRow>[];
  final logs = ref.watch(dailyLogsProvider).value ?? const <DailyLogRow>[];
  final intake = ref.watch(intakeKcalHistoryProvider).value ?? const {};
  final settings = ref.watch(settingsMapProvider).value ?? const {};
  final params = TdeeParams.fromAssumptions(a);

  final complete = {for (final l in logs) l.date: l.intakeComplete};
  final dates = {
    for (final m in metrics) m.date,
    for (final l in logs) l.date,
    ...intake.keys,
  };
  final weights = {for (final m in metrics) m.date: m.weightKg};
  final records = <DayRecord>[
    for (final d in dates)
      DayRecord(
        date: parseIsoDate(d),
        weightKg: weights[d],
        intakeKcal: intake[d]?.kcal,
        intakeComplete: (complete[d] ?? false) && !(intake[d]?.partial ?? true),
      ),
  ];
  final estimate = estimateTdee(records, asOf: today, params: params);
  final trend = weightTrend(records, params.emaAlpha);

  final bmr = mifflinBmr(
    weightKg: weight.kg,
    heightCm: profile.heightCm,
    ageYears: ageFromBirthYear(profile.birthYear, today),
    sex: Sex.parse(profile.sex),
  );
  final shift = ShiftConfig.fromClock(
    shiftStart: profile.shiftStart,
    shiftEnd: profile.shiftEnd,
    lunchStart: profile.lunchStart,
  );
  final todayLog = ref.watch(todayLogProvider);
  final dayEnergy = dailyEnergyTarget(
    bmr: bmr,
    dayType: dayTypeOf(todayLog),
    palWorkday: params.palWorkday,
    palOffday: params.palOffday,
    surplusKcal: params.bootstrapSurplusKcal,
    referenceHours: a[A.referenceShiftHours],
    hoursWorked: shift.hours,
  );
  final weekly = double.tryParse(settings[SettingKey.weeklyTargetKcal] ?? '');
  final adaptive = estimate.sufficient && weekly != null;
  final target = adaptive ? weekly : dayEnergy.kcal.toDouble();
  return EnergyStatus(
    weightKg: weight.kg,
    trend: trend,
    estimate: estimate,
    adaptive: adaptive,
    targetKcal: target,
    bmr: bmr,
    dayEnergy: dayEnergy,
    macros: macroTargets(
      kcal: target,
      weightKg: weight.kg,
      params: MacroParams.fromAssumptions(a),
    ),
    modeEs: adaptive
        ? 'ADAPTATIVO · ${estimate.validDays} días completos'
        : 'ARRANQUE (Mifflin) · ${estimate.validDays}/${estimate.requiredDays} días',
  );
});

/// Weekly review of the adaptive target (±150 kcal at most). Returns the
/// explanation when a review ran, null otherwise.
Future<String?> reviewWeeklyTarget(WidgetRef ref) async {
  final status = ref.read(energyStatusProvider);
  if (status == null || !status.estimate.sufficient) return null;
  final settings = ref.read(settingsMapProvider).value ?? const {};
  final today = ref.read(todayProvider);
  final reviewed = settings[SettingKey.weeklyTargetReviewed];
  if (reviewed != null) {
    try {
      if (daysBetween(parseIsoDate(reviewed), today) < 7) return null;
    } on FormatException {
      // A malformed date means the review must run again.
    }
  }
  final a = ref.read(currentAssumptionsProvider);
  final params = TdeeParams.fromAssumptions(a);
  final current = double.tryParse(settings[SettingKey.weeklyTargetKcal] ?? '') ??
      bootstrapTargetKcal(bmr: status.bmr, workday: true, params: params);
  final adjustment = weeklyTargetAdjustment(
    currentTargetKcal: current,
    estimate: status.estimate,
    params: params,
  );
  final repo = ref.read(settingsRepositoryProvider);
  await repo.set(SettingKey.weeklyTargetKcal, adjustment.newTargetKcal.toStringAsFixed(0));
  await repo.set(SettingKey.weeklyTargetReviewed, isoDate(today));
  return adjustment.reasonEs;
}
