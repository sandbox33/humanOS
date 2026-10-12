/// Adaptive energy expenditure from weight trend and logged intake.
///
/// The weight trend is an exponential moving average
/// `t_n = t_{n-1} + alpha * (w_n - t_{n-1})`; days without a weigh-in are
/// skipped. Over the last [TdeeParams.windowDays] days, expenditure is
/// `mean(intake) - slope_kg_per_day * kcalPerKg`, but only when at least
/// [TdeeParams.minValidDays] days have a complete intake log. Otherwise the
/// estimate is null ("datos insuficientes") and the Mifflin bootstrap is
/// used instead.
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
    required this.bootstrapSurplusKcal,
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
    bootstrapSurplusKcal: a[A.bootstrapSurplusKcal],
  );

  final double emaAlpha;
  final int windowDays;
  final int minValidDays;
  final double kcalPerKg;
  final double gainRateMinKgWeek;
  final double gainRateMaxKgWeek;
  final double targetStepMaxKcal;
  final double palWorkday;
  final double palOffday;
  final double bootstrapSurplusKcal;
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

/// Weekly review: moves the intake target toward the gain band
/// [gainRateMinKgWeek, gainRateMaxKgWeek], aiming at its middle, by at most
/// [TdeeParams.targetStepMaxKcal]. Without a sufficient estimate the target
/// never changes.
TargetAdjustment weeklyTargetAdjustment({
  required double currentTargetKcal,
  required TdeeEstimate estimate,
  required TdeeParams params,
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
  if (rate >= params.gainRateMinKgWeek && rate <= params.gainRateMaxKgWeek) {
    return TargetAdjustment(
      previousTargetKcal: currentTargetKcal,
      newTargetKcal: currentTargetKcal,
      reasonEs:
          'Ganancia de ${formatDecimal(rate, decimals: 2)} kg/semana, '
          'dentro del rango: el objetivo se mantiene.',
    );
  }
  final mid = (params.gainRateMinKgWeek + params.gainRateMaxKgWeek) / 2;
  final desired = tdee + mid * params.kcalPerKg / 7;
  final step = (desired - currentTargetKcal)
      .clamp(-params.targetStepMaxKcal, params.targetStepMaxKcal)
      .toDouble();
  final direction = step >= 0 ? 'sube' : 'baja';
  return TargetAdjustment(
    previousTargetKcal: currentTargetKcal,
    newTargetKcal: currentTargetKcal + step,
    reasonEs:
        'Ganancia de ${formatDecimal(rate, decimals: 2)} kg/semana, '
        'fuera del rango ${formatDecimal(params.gainRateMinKgWeek, decimals: 2)}'
        '–${formatDecimal(params.gainRateMaxKgWeek, decimals: 2)}: el objetivo '
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

/// Bootstrap intake target: Mifflin × PAL (workday or off-day) + surplus.
double bootstrapTargetKcal({
  required double bmr,
  required bool workday,
  required TdeeParams params,
}) =>
    bmr * (workday ? params.palWorkday : params.palOffday) +
    params.bootstrapSurplusKcal;
