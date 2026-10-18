/// Adaptive energy expenditure from weight trend and logged intake.
///
/// The weight trend is an exponential moving average
/// `t_n = t_{n-1} + alpha * (w_n - t_{n-1})`; days without a weigh-in are
/// skipped. Over the last [TdeeParams.windowDays] days, expenditure is
/// `mean(intake) - slope_kg_per_day * kcalPerKg`, but only when at least
/// [TdeeParams.minValidDays] days have a complete intake log. Otherwise the
/// estimate is null ("datos insuficientes") and the Mifflin bootstrap is
/// used instead. The bootstrap is Mifflin × PAL (from the job type) plus a
/// goal term: the somatotype surplus when gaining (a weak, descriptive
/// prior), zero when maintaining, the middle of the loss band when losing.
library;

import 'assumptions.dart';
import 'day.dart';
import 'format_es.dart';

/// One calendar day of weight and intake data.
class DayRecord {
  const DayRecord({
    required this.date,
    this.weightKg,
    this.intakeKcal,
    this.intakeComplete = false,
  });

  final DateTime date;
  final double? weightKg;

  /// Logged intake for the day; only trusted when [intakeComplete].
  final double? intakeKcal;

  /// The user confirmed every meal of the day was logged.
  final bool intakeComplete;

  bool get hasValidIntake => intakeComplete && intakeKcal != null;
}

/// Weight goal from the profile (`profile.goal`).
enum Goal {
  ganar('ganar', 'Ganar peso'),
  mantener('mantener', 'Mantener'),
  perder('perder', 'Perder grasa');

  const Goal(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static Goal parse(String? code) =>
      Goal.values.firstWhere((g) => g.code == code, orElse: () => Goal.ganar);
}

/// Self-described somatotype (`profile.somatotype`). Only a starting prior.
enum Somatotype {
  ecto('ecto', 'Ectomorfo'),
  meso('meso', 'Mesomorfo'),
  endo('endo', 'Endomorfo'),
  noSe('no_se', 'No sé');

  const Somatotype(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static Somatotype parse(String? code) => Somatotype.values.firstWhere(
    (s) => s.code == code,
    orElse: () => Somatotype.noSe,
  );
}

/// Physical demand of the job (`profile.job_type`), sets the PAL prior.
enum JobType {
  heavy('pesado', 'Trabajo manual pesado'),
  moderate('moderado', 'Trabajo moderado'),
  desk('escritorio', 'Trabajo de escritorio');

  const JobType(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static JobType parse(String? code) => JobType.values.firstWhere(
    (j) => j.code == code,
    orElse: () => JobType.heavy,
  );
}

/// Weekly rate band (kg/week) for a goal.
class RateBand {
  const RateBand(this.minKgWeek, this.maxKgWeek);
  final double minKgWeek;
  final double maxKgWeek;

  double get midKgWeek => (minKgWeek + maxKgWeek) / 2;
  bool contains(double rate) => rate >= minKgWeek && rate <= maxKgWeek;
}

/// Parameters read from the assumptions table.
class TdeeParams {
  const TdeeParams({
    required this.emaAlpha,
    required this.windowDays,
    required this.minValidDays,
    required this.kcalPerKg,
    required this.gainRateMinKgWeek,
    required this.gainRateMaxKgWeek,
    required this.targetStepMaxKcal,
    required this.palWorkday,
    required this.palOffday,
    required this.maintainRateMinKgWeek,
    required this.maintainRateMaxKgWeek,
    required this.loseRateMinKgWeek,
    required this.loseRateMaxKgWeek,
    required this.surplusEctoKcal,
    required this.surplusMesoKcal,
    required this.surplusEndoKcal,
    required this.surplusUnknownKcal,
    required this.palJobModerate,
    required this.palJobDesk,
  });

  factory TdeeParams.fromAssumptions(Assumptions a) => TdeeParams(
    emaAlpha: a[A.tdeeEmaAlpha],
    windowDays: a.integer(A.tdeeWindowDays),
    minValidDays: a.integer(A.tdeeMinValidDays),
    kcalPerKg: a[A.kcalPerKg],
    gainRateMinKgWeek: a[A.gainRateMinKgWeek],
    gainRateMaxKgWeek: a[A.gainRateMaxKgWeek],
    targetStepMaxKcal: a[A.targetStepMaxKcal],
    palWorkday: a[A.palWorkday],
    palOffday: a[A.palOffday],
    maintainRateMinKgWeek: a[A.maintainRateMinKgWeek],
    maintainRateMaxKgWeek: a[A.maintainRateMaxKgWeek],
    loseRateMinKgWeek: a[A.loseRateMinKgWeek],
    loseRateMaxKgWeek: a[A.loseRateMaxKgWeek],
    surplusEctoKcal: a[A.surplusEctoKcal],
    surplusMesoKcal: a[A.surplusMesoKcal],
    surplusEndoKcal: a[A.surplusEndoKcal],
    surplusUnknownKcal: a[A.surplusUnknownKcal],
    palJobModerate: a[A.palJobModerate],
    palJobDesk: a[A.palJobDesk],
  );

  final double emaAlpha;
  final int windowDays;
  final int minValidDays;
  final double kcalPerKg;
  final double gainRateMinKgWeek;
  final double gainRateMaxKgWeek;
  final double targetStepMaxKcal;

  /// PAL of a heavy manual workday.
  final double palWorkday;
  final double palOffday;
  final double maintainRateMinKgWeek;
  final double maintainRateMaxKgWeek;
  final double loseRateMinKgWeek;
  final double loseRateMaxKgWeek;
  final double surplusEctoKcal;
  final double surplusMesoKcal;
  final double surplusEndoKcal;
  final double surplusUnknownKcal;
  final double palJobModerate;
  final double palJobDesk;

  RateBand rateBand(Goal goal) => switch (goal) {
    Goal.ganar => RateBand(gainRateMinKgWeek, gainRateMaxKgWeek),
    Goal.mantener => RateBand(maintainRateMinKgWeek, maintainRateMaxKgWeek),
    Goal.perder => RateBand(loseRateMinKgWeek, loseRateMaxKgWeek),
  };

  double surplusFor(Somatotype somatotype) => switch (somatotype) {
    Somatotype.ecto => surplusEctoKcal,
    Somatotype.meso => surplusMesoKcal,
    Somatotype.endo => surplusEndoKcal,
    Somatotype.noSe => surplusUnknownKcal,
  };

  double palFor(JobType job) => switch (job) {
    JobType.heavy => palWorkday,
    JobType.moderate => palJobModerate,
    JobType.desk => palJobDesk,
  };
}

/// A point of the smoothed weight trend.
class TrendPoint {
  const TrendPoint({
    required this.date,
    required this.trendKg,
    required this.measured,
  });

  final DateTime date;
  final double trendKg;

  /// Whether the user weighed in on this day (the trend moved).
  final bool measured;
}

/// Exponential moving average of weight. Days without weight keep the
/// previous trend value and are marked as not measured; days before the
/// first weigh-in produce no point.
List<TrendPoint> weightTrend(List<DayRecord> records, double alpha) {
  final sorted = [...records]..sort((a, b) => a.date.compareTo(b.date));
  final points = <TrendPoint>[];
  double? trend;
  for (final record in sorted) {
    final weight = record.weightKg;
    if (weight != null) {
      trend = trend == null ? weight : trend + alpha * (weight - trend);
      points.add(
        TrendPoint(date: dateOnly(record.date), trendKg: trend, measured: true),
      );
    } else if (trend != null) {
      points.add(
        TrendPoint(
          date: dateOnly(record.date),
          trendKg: trend,
          measured: false,
        ),
      );
    }
  }
  return points;
}

/// Result of [estimateTdee].
class TdeeEstimate {
  const TdeeEstimate({
    required this.tdeeKcal,
    required this.validDays,
    required this.requiredDays,
    required this.slopeKgPerDay,
    required this.trendKg,
    required this.meanIntakeKcal,
    required this.reasonEs,
  });

  /// Estimated expenditure, or null when data is insufficient.
  final double? tdeeKcal;
  final int validDays;
  final int requiredDays;
  final double? slopeKgPerDay;
  final double? trendKg;
  final double? meanIntakeKcal;
  final String reasonEs;

  bool get sufficient => tdeeKcal != null;

  double? get weeklyRateKg => slopeKgPerDay == null ? null : slopeKgPerDay! * 7;
}

/// Least-squares slope of y over x. Requires at least two distinct x.
double? _slope(List<double> xs, List<double> ys) {
  if (xs.length < 2) return null;
  final n = xs.length;
  final meanX = xs.reduce((a, b) => a + b) / n;
  final meanY = ys.reduce((a, b) => a + b) / n;
  var num = 0.0;
  var den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (xs[i] - meanX) * (ys[i] - meanY);
    den += (xs[i] - meanX) * (xs[i] - meanX);
  }
  if (den == 0) return null;
  return num / den;
}

/// Estimates expenditure as of [asOf] (inclusive).
TdeeEstimate estimateTdee(
  List<DayRecord> records, {
  required DateTime asOf,
  required TdeeParams params,
}) {
  final end = dateOnly(asOf);
  final start = addDays(end, -(params.windowDays - 1));
  bool inWindow(DateTime d) {
    final day = dateOnly(d);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  final upToEnd = records.where((r) => !dateOnly(r.date).isAfter(end)).toList();
  final trend = weightTrend(upToEnd, params.emaAlpha);
  final latestTrend = trend.isEmpty ? null : trend.last.trendKg;

  final validIntakes = <DateTime, double>{};
  for (final r in upToEnd) {
    if (inWindow(r.date) && r.hasValidIntake) {
      validIntakes[dateOnly(r.date)] = r.intakeKcal!;
    }
  }
  final validDays = validIntakes.length;
  if (validDays < params.minValidDays) {
    return TdeeEstimate(
      tdeeKcal: null,
      validDays: validDays,
      requiredDays: params.minValidDays,
      slopeKgPerDay: null,
      trendKg: latestTrend,
      meanIntakeKcal: null,
      reasonEs:
          'Datos insuficientes: $validDays de ${params.minValidDays} '
          'días con ingesta completa en los últimos ${params.windowDays} días.',
    );
  }

  final measured = trend.where((p) => p.measured && inWindow(p.date)).toList();
  final xs = [for (final p in measured) daysBetween(start, p.date).toDouble()];
  final ys = [for (final p in measured) p.trendKg];
  final slope = _slope(xs, ys);
  if (slope == null) {
    return TdeeEstimate(
      tdeeKcal: null,
      validDays: validDays,
      requiredDays: params.minValidDays,
      slopeKgPerDay: null,
      trendKg: latestTrend,
      meanIntakeKcal: null,
      reasonEs:
          'Datos insuficientes: hacen falta al menos dos pesajes en '
          'días distintos dentro de la ventana.',
    );
  }

  final meanIntake =
      validIntakes.values.reduce((a, b) => a + b) / validIntakes.length;
  final tdee = meanIntake - slope * params.kcalPerKg;
  return TdeeEstimate(
    tdeeKcal: tdee,
    validDays: validDays,
    requiredDays: params.minValidDays,
    slopeKgPerDay: slope,
    trendKg: latestTrend,
    meanIntakeKcal: meanIntake,
    reasonEs:
        'Gasto estimado con $validDays días completos: ingesta media '
        '${formatWhole(meanIntake)} kcal, tendencia '
        '${formatDecimal(slope * 7, decimals: 2)} kg/semana.',
  );
}

/// Result of the weekly target review.
class TargetAdjustment {
  const TargetAdjustment({
    required this.previousTargetKcal,
    required this.newTargetKcal,
    required this.reasonEs,
  });

  final double previousTargetKcal;
  final double newTargetKcal;
  final String reasonEs;

  double get stepKcal => newTargetKcal - previousTargetKcal;
  bool get changed => stepKcal != 0;
}

/// Weekly review: moves the intake target toward the rate band of [goal]
/// (ganar +0.15…+0.30 kg/week by default), aiming at its middle, by at most
/// [TdeeParams.targetStepMaxKcal]. Without a sufficient estimate the target
/// never changes.
TargetAdjustment weeklyTargetAdjustment({
  required double currentTargetKcal,
  required TdeeEstimate estimate,
  required TdeeParams params,
  Goal goal = Goal.ganar,
}) {
  final tdee = estimate.tdeeKcal;
  final rate = estimate.weeklyRateKg;
  if (tdee == null || rate == null) {
    return TargetAdjustment(
      previousTargetKcal: currentTargetKcal,
      newTargetKcal: currentTargetKcal,
      reasonEs: 'El objetivo no cambia: ${estimate.reasonEs}',
    );
  }
  final band = params.rateBand(goal);
  final change = 'Cambio de ${formatDecimal(rate, decimals: 2)} kg/semana';
  if (band.contains(rate)) {
    return TargetAdjustment(
      previousTargetKcal: currentTargetKcal,
      newTargetKcal: currentTargetKcal,
      reasonEs: '$change, dentro del rango: el objetivo se mantiene.',
    );
  }
  final desired = tdee + band.midKgWeek * params.kcalPerKg / 7;
  final step = (desired - currentTargetKcal)
      .clamp(-params.targetStepMaxKcal, params.targetStepMaxKcal)
      .toDouble();
  final direction = step >= 0 ? 'sube' : 'baja';
  return TargetAdjustment(
    previousTargetKcal: currentTargetKcal,
    newTargetKcal: currentTargetKcal + step,
    reasonEs:
        '$change, fuera del rango ${formatDecimal(band.minKgWeek, decimals: 2)}'
        '–${formatDecimal(band.maxKgWeek, decimals: 2)}: el objetivo '
        '$direction ${formatWhole(step.abs())} kcal.',
  );
}

/// Biological sex used by the Mifflin–St Jeor equation.
enum Sex {
  male('male'),
  female('female');

  const Sex(this.code);
  final String code;

  static Sex parse(String code) => code == female.code ? Sex.female : Sex.male;
}

/// Mifflin–St Jeor resting energy expenditure in kcal/day.
double mifflinBmr({
  required double weightKg,
  required double heightCm,
  required int ageYears,
  required Sex sex,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * ageYears;
  return sex == Sex.male ? base + 5 : base - 161;
}

/// Age in whole years from a birth year (birthday not stored).
int ageFromBirthYear(int birthYear, DateTime today) => today.year - birthYear;

/// PAL for the day: the job PAL on workdays, never more than that on an
/// off day.
double dayPal({
  required bool workday,
  required JobType job,
  required TdeeParams params,
}) {
  final jobPal = params.palFor(job);
  if (workday) return jobPal;
  return params.palOffday < jobPal ? params.palOffday : jobPal;
}

/// Goal term of the bootstrap: somatotype surplus when gaining, zero when
/// maintaining, the middle of the loss band (negative) when losing.
double bootstrapGoalKcal({
  required Goal goal,
  required Somatotype somatotype,
  required TdeeParams params,
}) => switch (goal) {
  Goal.ganar => params.surplusFor(somatotype),
  Goal.mantener => 0,
  Goal.perder => params.rateBand(Goal.perder).midKgWeek * params.kcalPerKg / 7,
};

/// Bootstrap intake target: Mifflin × PAL + goal term. Used until the
/// adaptive estimate has enough complete days.
double bootstrapTargetKcal({
  required double bmr,
  required bool workday,
  required TdeeParams params,
  Goal goal = Goal.ganar,
  Somatotype somatotype = Somatotype.noSe,
  JobType job = JobType.heavy,
}) =>
    bmr * dayPal(workday: workday, job: job, params: params) +
    bootstrapGoalKcal(goal: goal, somatotype: somatotype, params: params);
