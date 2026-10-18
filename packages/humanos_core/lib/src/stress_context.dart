/// Context question for an unusually high heart rate outside exercise.
///
/// Runs only when the device shares heart rate outside exercise (capability
/// probe). It is evaluated in batch over the day's samples, never as a live
/// "stress" alert. A sample is unusual when it is more than 2 SD above the
/// personal baseline for that hour of the day (last 28 days, at least 10
/// samples for that hour), outside any workout (plus a recovery margin),
/// outside the taller geofence and outside shift hours. At most one
/// question a day (notification policy), answered through BUZÓN. The
/// question asks what was happening; it never labels it as stress.
library;

import 'dart:math' as math;

import 'assumptions.dart';
import 'day.dart';
import 'format_es.dart';

class HrSample {
  const HrSample({required this.at, required this.bpm});

  /// Local wall-clock time of the sample.
  final DateTime at;
  final double bpm;
}

class TimeInterval {
  const TimeInterval(this.start, this.end);
  final DateTime start;
  final DateTime end;

  bool contains(DateTime t) => !t.isBefore(start) && !t.isAfter(end);
}

class StressParams {
  const StressParams({
    required this.sdThreshold,
    required this.baselineDays,
    required this.minSamples,
    required this.workoutMarginMin,
  });

  factory StressParams.fromAssumptions(Assumptions a) => StressParams(
    sdThreshold: a[A.stressSdThreshold],
    baselineDays: a.integer(A.stressBaselineDays),
    minSamples: a.integer(A.stressMinBaselineSamples),
    workoutMarginMin: a.integer(A.stressWorkoutMarginMin),
  );

  final double sdThreshold;
  final int baselineDays;
  final int minSamples;
  final int workoutMarginMin;
}

class HourBaseline {
  const HourBaseline({
    required this.hour,
    required this.mean,
    required this.sd,
    required this.n,
  });

  final int hour;
  final double mean;
  final double sd;
  final int n;
}

bool _inAny(DateTime t, List<TimeInterval> intervals, int marginMin) {
  for (final i in intervals) {
    final end = i.end.add(Duration(minutes: marginMin));
    if (!t.isBefore(i.start) && !t.isAfter(end)) return true;
  }
  return false;
}

/// Mean and SD per hour of day from the samples of the [baselineDays] days
/// before [day], excluding workouts (plus the margin).
Map<int, HourBaseline> hourlyBaselines(
  List<HrSample> samples, {
  required DateTime day,
  required List<TimeInterval> workouts,
  required StressParams params,
}) {
  final end = dateOnly(day);
  final start = addDays(end, -params.baselineDays);
  final byHour = <int, List<double>>{};
  for (final s in samples) {
    final d = dateOnly(s.at);
    if (d.isBefore(start) || !d.isBefore(end)) continue;
    if (_inAny(s.at, workouts, params.workoutMarginMin)) continue;
    byHour.putIfAbsent(s.at.hour, () => []).add(s.bpm);
  }
  final result = <int, HourBaseline>{};
  byHour.forEach((hour, values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    var sq = 0.0;
    for (final v in values) {
      sq += (v - mean) * (v - mean);
    }
    final sd = values.length < 2 ? 0.0 : math.sqrt(sq / (values.length - 1));
    result[hour] = HourBaseline(
      hour: hour,
      mean: mean,
      sd: sd,
      n: values.length,
    );
  });
  return result;
}

/// Context answers offered in BUZÓN.
enum StressContextAnswer {
  taller('taller', 'Taller'),
  gym('gym', 'Gimnasio'),
  trabajo('trabajo', 'Trabajo'),
  conflicto('conflicto', 'Discusión o tensión'),
  otro('otro', 'Otro');

  const StressContextAnswer(this.code, this.labelEs);
  final String code;
  final String labelEs;
}

class StressContextCheck {
  const StressContextCheck({
    required this.ask,
    required this.reasonEs,
    this.sample,
    this.baseline,
    this.zScore,
  });

  final bool ask;
  final String reasonEs;
  final HrSample? sample;
  final HourBaseline? baseline;
  final double? zScore;

  /// The question for the inbox notification, neutral wording.
  String? get questionEs {
    final s = sample, b = baseline;
    if (!ask || s == null || b == null) return null;
    final clock = formatClock(s.at.hour * 60 + s.at.minute);
    return 'A las $clock tu pulso estuvo en ${formatWhole(s.bpm)} lpm; lo '
        'habitual a esa hora es ${formatWhole(b.mean)}. ¿Qué estabas '
        'haciendo?';
  }
}

/// Looks for the most unusual sample of [day]. [hrOutsideExercise] is the
/// capability; [isExcluded] tells whether a time is in shift hours or in
/// the taller geofence.
StressContextCheck checkStressContext({
  required List<HrSample> samples,
  required DateTime day,
  required bool hrOutsideExercise,
  required List<TimeInterval> workouts,
  required bool Function(DateTime at) isExcluded,
  required bool alreadyAskedToday,
  required StressParams params,
}) {
  if (!hrOutsideExercise) {
    return const StressContextCheck(
      ask: false,
      reasonEs:
          'Tu dispositivo no comparte el pulso fuera del ejercicio: esta '
          'función queda apagada.',
    );
  }
  if (alreadyAskedToday) {
    return const StressContextCheck(
      ask: false,
      reasonEs: 'Ya se preguntó una vez hoy.',
    );
  }
  final baselines = hourlyBaselines(
    samples,
    day: day,
    workouts: workouts,
    params: params,
  );
  final target = dateOnly(day);
  HrSample? best;
  HourBaseline? bestBase;
  double? bestZ;
  for (final s in samples) {
    if (dateOnly(s.at) != target) continue;
    if (_inAny(s.at, workouts, params.workoutMarginMin)) continue;
    if (isExcluded(s.at)) continue;
    final b = baselines[s.at.hour];
    if (b == null || b.n < params.minSamples || b.sd <= 0) continue;
    final z = (s.bpm - b.mean) / b.sd;
    if (z > params.sdThreshold && (bestZ == null || z > bestZ)) {
      best = s;
      bestBase = b;
      bestZ = z;
    }
  }
  if (best == null) {
    return const StressContextCheck(
      ask: false,
      reasonEs: 'Sin lecturas fuera de lo habitual hoy.',
    );
  }
  return StressContextCheck(
    ask: true,
    reasonEs:
        'Pulso ${formatDecimal(bestZ!)} DE por encima de tu base para esa '
        'hora.',
    sample: best,
    baseline: bestBase,
    zScore: bestZ,
  );
}
