/// Daily readiness band (VERDE / AMARILLO / ROJO).
///
/// HRV path when enough ln rMSSD data exists: the 7-day mean is compared
/// with the 60-day mean − 0.5 SD (no fixed population baseline). Otherwise
/// resting heart rate is compared with the previous 28 days (> mean + 1 SD).
/// Short sleep, a HIGH-effort shift and sleep debt each add one AMARILLO
/// flag. Two or more flags make ROJO, which only *suggests* postponing 24 h;
/// it never blocks a session. Without any data the band is VERDE with a
/// "sin datos" note. Nights without data never count as debt.
library;

import 'dart:math' as math;

import 'assumptions.dart';
import 'day.dart';
import 'format_es.dart';

enum ReadinessBand {
  verde('VERDE'),
  amarillo('AMARILLO'),
  rojo('ROJO');

  const ReadinessBand(this.code);
  final String code;

  static ReadinessBand? parse(String? code) {
    for (final band in ReadinessBand.values) {
      if (band.code == code) return band;
    }
    return null;
  }
}

/// Self-reported shift effort stored in `daily_logs.work_effort`.
enum WorkEffort {
  off('OFF', 'LIBRE'),
  low('LOW', 'BAJO'),
  medium('MEDIUM', 'MEDIO'),
  high('HIGH', 'ALTO');

  const WorkEffort(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static WorkEffort? parse(String? code) {
    for (final effort in WorkEffort.values) {
      if (effort.code == code) return effort;
    }
    return null;
  }
}

/// Recovery data for one day. Sleep belongs to the night that ended on
/// [date] (wake-up day).
class DailyRecovery {
  const DailyRecovery({
    required this.date,
    this.hrvRmssdMs,
    this.rhrBpm,
    this.sleepMinutes,
    this.workEffort,
  });

  final DateTime date;
  final double? hrvRmssdMs;
  final double? rhrBpm;
  final double? sleepMinutes;
  final WorkEffort? workEffort;
}

class ReadinessParams {
  const ReadinessParams({
    required this.hrvShortDays,
    required this.hrvLongDays,
    required this.hrvSdFactor,
    required this.hrvMinShortSamples,
    required this.hrvMinLongSamples,
    required this.rhrBaselineDays,
    required this.rhrSdFactor,
    required this.rhrMinBaselineSamples,
    required this.sleepMinMinutes,
    required this.sleepTargetH,
    required this.sleepDebtMaxH,
    required this.sleepDebtNights,
  });

  factory ReadinessParams.fromAssumptions(Assumptions a) => ReadinessParams(
    hrvShortDays: a.integer(A.hrvShortDays),
    hrvLongDays: a.integer(A.hrvLongDays),
    hrvSdFactor: a[A.hrvSdFactor],
    hrvMinShortSamples: a.integer(A.hrvMinShortSamples),
    hrvMinLongSamples: a.integer(A.hrvMinLongSamples),
    rhrBaselineDays: a.integer(A.rhrBaselineDays),
    rhrSdFactor: a[A.rhrSdFactor],
    rhrMinBaselineSamples: a.integer(A.rhrMinBaselineSamples),
    sleepMinMinutes: a[A.sleepMinMinutes],
    sleepTargetH: a[A.sleepTargetH],
    sleepDebtMaxH: a[A.sleepDebtMaxH],
    sleepDebtNights: a.integer(A.sleepDebtNights),
  );

  final int hrvShortDays;
  final int hrvLongDays;
  final double hrvSdFactor;
  final int hrvMinShortSamples;
  final int hrvMinLongSamples;
  final int rhrBaselineDays;
  final double rhrSdFactor;
  final int rhrMinBaselineSamples;
  final double sleepMinMinutes;
  final double sleepTargetH;
  final double sleepDebtMaxH;
  final int sleepDebtNights;
}

/// Which physiological signal drove the cardiac part of the assessment.
enum ReadinessPath { hrv, rhr, none }

/// Identifiers of AMARILLO flags.
enum ReadinessFlag { hrvLow, rhrHigh, shortSleep, highEffort, sleepDebt }

class ReadinessResult {
  const ReadinessResult({
    required this.band,
    required this.flags,
    required this.reasonsEs,
    required this.path,
    required this.noData,
    this.hrvShortMean,
    this.hrvLongMean,
    this.hrvLongSd,
    this.rhrToday,
    this.rhrMean,
    this.rhrSd,
    this.sleepLastNightMin,
    this.sleepDebtH,
  });

  final ReadinessBand band;
  final List<ReadinessFlag> flags;
  final List<String> reasonsEs;
  final ReadinessPath path;
  final bool noData;
  final double? hrvShortMean;
  final double? hrvLongMean;
  final double? hrvLongSd;
  final double? rhrToday;
  final double? rhrMean;
  final double? rhrSd;
  final double? sleepLastNightMin;
  final double? sleepDebtH;

  /// ROJO suggests postponing the session 24 h. It is a suggestion only.
  bool get suggestPostpone => band == ReadinessBand.rojo;
}

double _mean(List<double> values) =>
    values.reduce((a, b) => a + b) / values.length;

/// Sample standard deviation (n − 1). Zero for fewer than two values.
double sampleSd(List<double> values) {
  if (values.length < 2) return 0;
  final m = _mean(values);
  var sum = 0.0;
  for (final v in values) {
    sum += (v - m) * (v - m);
  }
  return math.sqrt(sum / (values.length - 1));
}

/// Assesses readiness for [today] from [history] (any order).
ReadinessResult assessReadiness(
  List<DailyRecovery> history, {
  required DateTime today,
  required ReadinessParams params,
}) {
  final day = dateOnly(today);
  final byDate = <DateTime, DailyRecovery>{
    for (final r in history) dateOnly(r.date): r,
  };
  final todayRecord = byDate[day];
  final flags = <ReadinessFlag>[];
  final reasons = <String>[];
  var anyData = false;

  List<double> collect(
    int fromOffset,
    int toOffset,
    double? Function(DailyRecovery) pick,
  ) {
    final values = <double>[];
    for (var offset = fromOffset; offset <= toOffset; offset++) {
      final record = byDate[addDays(day, -offset)];
      final value = record == null ? null : pick(record);
      if (value != null) values.add(value);
    }
    return values;
  }

  double? lnRmssd(DailyRecovery r) {
    final v = r.hrvRmssdMs;
    return v == null || v <= 0 ? null : math.log(v);
  }

  // Cardiac signal: HRV when available, otherwise resting heart rate.
  var path = ReadinessPath.none;
  double? hrvShortMean, hrvLongMean, hrvLongSd;
  double? rhrToday, rhrMean, rhrSd;
  final shortHrv = collect(0, params.hrvShortDays - 1, lnRmssd);
  final longHrv = collect(0, params.hrvLongDays - 1, lnRmssd);
  if (shortHrv.length >= params.hrvMinShortSamples &&
      longHrv.length >= params.hrvMinLongSamples) {
    path = ReadinessPath.hrv;
    anyData = true;
    hrvShortMean = _mean(shortHrv);
    hrvLongMean = _mean(longHrv);
    hrvLongSd = sampleSd(longHrv);
    final lower = hrvLongMean - params.hrvSdFactor * hrvLongSd;
    if (hrvShortMean < lower) {
      flags.add(ReadinessFlag.hrvLow);
      reasons.add(
        'VFC (ln rMSSD, media de ${params.hrvShortDays} días) por '
        'debajo de tu rango normal: ${formatDecimal(hrvShortMean, decimals: 2)} '
        'frente a ${formatDecimal(hrvLongMean, decimals: 2)} − '
        '${formatDecimal(params.hrvSdFactor)} DE.',
      );
    }
  } else {
    rhrToday = todayRecord?.rhrBpm;
    final baseline = collect(1, params.rhrBaselineDays, (r) => r.rhrBpm);
    if (rhrToday != null) anyData = true;
    if (rhrToday != null && baseline.length >= params.rhrMinBaselineSamples) {
      path = ReadinessPath.rhr;
      rhrMean = _mean(baseline);
      rhrSd = sampleSd(baseline);
      if (rhrToday > rhrMean + params.rhrSdFactor * rhrSd) {
        flags.add(ReadinessFlag.rhrHigh);
        reasons.add(
          'FC en reposo elevada: ${formatWhole(rhrToday)} lpm frente '
          'a tu media de ${formatWhole(rhrMean)} ± '
          '${formatDecimal(rhrSd)} lpm.',
        );
      }
    }
  }

  final sleepLastNight = todayRecord?.sleepMinutes;
  if (sleepLastNight != null) {
    anyData = true;
    if (sleepLastNight < params.sleepMinMinutes) {
      flags.add(ReadinessFlag.shortSleep);
      reasons.add(
        'Dormiste ${formatHoursMinutes(sleepLastNight)} '
        '(menos de ${formatHoursMinutes(params.sleepMinMinutes)}).',
      );
    }
  }

  final effort = todayRecord?.workEffort;
  if (effort != null) {
    anyData = true;
    if (effort == WorkEffort.high) {
      flags.add(ReadinessFlag.highEffort);
      reasons.add('Turno de esfuerzo ALTO hoy.');
    }
  }

  double? debtH;
  final nights = collect(0, params.sleepDebtNights - 1, (r) => r.sleepMinutes);
  if (nights.isNotEmpty) {
    debtH = nights
        .map((m) => params.sleepTargetH - m / 60)
        .reduce((a, b) => a + b);
    if (debtH > params.sleepDebtMaxH) {
      flags.add(ReadinessFlag.sleepDebt);
      reasons.add(
        'Deuda de sueño de ${formatDecimal(debtH)} h en las últimas '
        '${nights.length} noches con registro.',
      );
    }
  }

  if (!anyData) {
    return const ReadinessResult(
      band: ReadinessBand.verde,
      flags: [],
      reasonsEs: ['Sin datos de recuperación: se asume VERDE.'],
      path: ReadinessPath.none,
      noData: true,
    );
  }

  final band = switch (flags.length) {
    0 => ReadinessBand.verde,
    1 => ReadinessBand.amarillo,
    _ => ReadinessBand.rojo,
  };
  if (band == ReadinessBand.rojo) {
    reasons.add(
      'Se sugiere posponer la sesión 24 h. Puedes entrenar igual: '
      'quedará registrado.',
    );
  }
  if (band == ReadinessBand.verde) {
    reasons.add('Sin señales de fatiga en los datos disponibles.');
  }
  return ReadinessResult(
    band: band,
    flags: List.unmodifiable(flags),
    reasonsEs: List.unmodifiable(reasons),
    path: path,
    noData: false,
    hrvShortMean: hrvShortMean,
    hrvLongMean: hrvLongMean,
    hrvLongSd: hrvLongSd,
    rhrToday: rhrToday,
    rhrMean: rhrMean,
    rhrSd: rhrSd,
    sleepLastNightMin: sleepLastNight,
    sleepDebtH: debtH,
  );
}
