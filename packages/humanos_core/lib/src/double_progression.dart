/// Heavy Duty double progression, stall handling and session planning.
///
/// One working set per exercise. When every valid rep reaches `rep_max` the
/// next load is `load + min_increment_kg` (assisted machines: less
/// assistance). When the reps overshoot the range (> rep_max + 5 or > 20)
/// the load jumps to the e1RM-estimated load for 10 reps (Epley), rounded
/// down to the available increment. Two consecutive sessions below the
/// previous one add rest
/// days; three start a deload week (RIR 2–3, never to failure) followed by a
/// re-test. Sessions in ROJO, overridden, deload or re-test sessions are
/// excluded from stall counting, and counting restarts after each re-test.
library;

import 'assumptions.dart';
import 'day.dart';
import 'e1rm.dart';
import 'format_es.dart';
import 'readiness.dart';

enum TrainingTemplate {
  a('A'),
  b('B'),
  baseline('BASELINE');

  const TrainingTemplate(this.code);
  final String code;

  static TrainingTemplate parse(String code) => TrainingTemplate.values
      .firstWhere((t) => t.code == code, orElse: () => TrainingTemplate.a);
}

enum SessionMode {
  normal('normal', 'NORMAL'),
  deload('deload', 'DESCARGA'),
  retest('retest', 'RE-TEST');

  const SessionMode(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static SessionMode parse(String? code) => SessionMode.values.firstWhere(
    (m) => m.code == code,
    orElse: () => SessionMode.normal,
  );
}

/// Static description of an exercise (from the reference database).
class ExerciseSpec {
  const ExerciseSpec({
    required this.id,
    required this.nameEs,
    required this.repMin,
    required this.repMax,
    required this.minIncrementKg,
    required this.failureSafe,
    this.assisted = false,
    this.timed = false,
  });

  final int id;
  final String nameEs;
  final int repMin;
  final int repMax;
  final double minIncrementKg;

  /// False for free squat, deadlift, RDL: never taken to failure.
  final bool failureSafe;

  /// Load is machine assistance: progressing means *less* load.
  final bool assisted;

  /// Reps are seconds held (farmer hold, dead hang).
  final bool timed;
}

/// A logged set.
class SetRecord {
  const SetRecord({
    required this.exerciseId,
    required this.loadKg,
    required this.reps,
    required this.validReps,
    required this.reachedFailure,
    this.isWarmup = false,
    this.restPauseReps = 0,
  });

  final int exerciseId;
  final double loadKg;
  final int reps;
  final int validReps;
  final bool reachedFailure;
  final bool isWarmup;
  final int restPauseReps;
}

/// A logged session.
class SessionRecord {
  const SessionRecord({
    required this.date,
    required this.template,
    required this.sets,
    this.mode = SessionMode.normal,
    this.readiness,
    this.overridden = false,
  });

  final DateTime date;
  final TrainingTemplate template;
  final SessionMode mode;
  final ReadinessBand? readiness;
  final bool overridden;
  final List<SetRecord> sets;

  /// Whether this session can count toward stall detection.
  bool get countsForStalls =>
      mode == SessionMode.normal &&
      readiness != ReadinessBand.rojo &&
      !overridden;

  /// The working set used for progression of [exerciseId], if any.
  SetRecord? workingSet(int exerciseId, {bool assisted = false}) {
    SetRecord? best;
    for (final set in sets) {
      if (set.exerciseId != exerciseId || set.isWarmup) continue;
      if (best == null) {
        best = set;
        continue;
      }
      final harder = assisted
          ? set.loadKg < best.loadKg
          : set.loadKg > best.loadKg;
      if (harder ||
          (set.loadKg == best.loadKg && set.validReps > best.validReps)) {
        best = set;
      }
    }
    return best;
  }
}

class ProgressionParams {
  const ProgressionParams({
    required this.restDaysMin,
    required this.restDaysMax,
    required this.stallRestThreshold,
    required this.stallExtraRestDays,
    required this.stallDeloadThreshold,
    required this.deloadDays,
    required this.deloadRirMin,
    required this.deloadRirMax,
    required this.warmup1Pct,
    required this.warmup1Reps,
    required this.warmup2Pct,
    required this.warmup2Reps,
    required this.baselineRepMin,
    required this.baselineRepMax,
    required this.jumpRepsOverMax,
    required this.jumpRepsAbsolute,
    required this.jumpTargetReps,
  });

  factory ProgressionParams.fromAssumptions(Assumptions a) => ProgressionParams(
    restDaysMin: a.integer(A.restDaysMin),
    restDaysMax: a.integer(A.restDaysMax),
    stallRestThreshold: a.integer(A.stallRestThreshold),
    stallExtraRestDays: a.integer(A.stallExtraRestDays),
    stallDeloadThreshold: a.integer(A.stallDeloadThreshold),
    deloadDays: a.integer(A.deloadDays),
    deloadRirMin: a.integer(A.deloadRirMin),
    deloadRirMax: a.integer(A.deloadRirMax),
    warmup1Pct: a[A.warmup1Pct],
    warmup1Reps: a.integer(A.warmup1Reps),
    warmup2Pct: a[A.warmup2Pct],
    warmup2Reps: a.integer(A.warmup2Reps),
    baselineRepMin: a.integer(A.baselineRepTargetMin),
    baselineRepMax: a.integer(A.baselineRepTargetMax),
    jumpRepsOverMax: a.integer(A.jumpRepsOverMax),
    jumpRepsAbsolute: a.integer(A.jumpRepsAbsolute),
    jumpTargetReps: a.integer(A.jumpTargetReps),
  );

  final int restDaysMin;
  final int restDaysMax;
  final int stallRestThreshold;
  final int stallExtraRestDays;
  final int stallDeloadThreshold;
  final int deloadDays;
  final int deloadRirMin;
  final int deloadRirMax;
  final double warmup1Pct;
  final int warmup1Reps;
  final double warmup2Pct;
  final int warmup2Reps;
  final int baselineRepMin;
  final int baselineRepMax;
  final int jumpRepsOverMax;
  final int jumpRepsAbsolute;
  final int jumpTargetReps;
}

enum ProgressionAction { start, increase, jump, hold, deload, retest }

class ExerciseTarget {
  const ExerciseTarget({
    required this.exerciseId,
    required this.action,
    required this.loadKg,
    required this.repTarget,
    required this.stallCount,
    required this.previousBest,
    required this.messageEs,
    this.rirTarget,
  });

  final int exerciseId;
  final ProgressionAction action;

  /// Suggested load; null when there is no history (find it in the
  /// baseline session).
  final double? loadKg;
  final int repTarget;
  final int stallCount;

  /// The set to beat ("TARGET TO SMASH").
  final SetRecord? previousBest;

  /// Reps in reserve to stop at (deload, or exercises never to failure).
  final int? rirTarget;
  final String messageEs;
}

List<SessionRecord> _sorted(List<SessionRecord> history) =>
    [...history]..sort((a, b) => a.date.compareTo(b.date));

/// Consecutive regressions at the end of the eligible history of [spec].
int stallCount(ExerciseSpec spec, List<SessionRecord> history) {
  final sorted = _sorted(history);
  var start = 0;
  for (var i = 0; i < sorted.length; i++) {
    if (sorted[i].mode == SessionMode.retest) start = i;
  }
  final sets = <SetRecord>[];
  for (final session in sorted.sublist(start)) {
    final isRetestAnchor = session.mode == SessionMode.retest;
    if (!session.countsForStalls && !isRetestAnchor) continue;
    final set = session.workingSet(spec.id, assisted: spec.assisted);
    if (set != null) sets.add(set);
  }
  var count = 0;
  for (var i = sets.length - 1; i >= 1; i--) {
    final cur = sets[i];
    final prev = sets[i - 1];
    final notEasier = spec.assisted
        ? cur.loadKg >= prev.loadKg
        : cur.loadKg <= prev.loadKg;
    if (notEasier && cur.validReps < prev.validReps) {
      count++;
    } else {
      break;
    }
  }
  return count;
}

double _round(double value, double step) {
  if (step <= 0) return value;
  return (value / step).round() * step;
}

/// Target for the next set of [spec] given the session [mode].
ExerciseTarget nextExerciseTarget(
  ExerciseSpec spec,
  List<SessionRecord> history, {
  required SessionMode mode,
  required ProgressionParams params,
}) {
  final sorted = _sorted(history);
  SetRecord? last;
  SetRecord? best;
  for (final session in sorted) {
    final set = session.workingSet(spec.id, assisted: spec.assisted);
    if (set == null) continue;
    if (session.mode != SessionMode.deload) last = set;
    if (best == null ||
        (spec.assisted
            ? set.loadKg < best.loadKg ||
                  (set.loadKg == best.loadKg && set.validReps > best.validReps)
            : set.loadKg > best.loadKg ||
                  (set.loadKg == best.loadKg &&
                      set.validReps > best.validReps))) {
      best = set;
    }
  }
  final stalls = stallCount(spec, history);
  final unit = spec.timed ? 's' : 'reps';
  final rir = spec.failureSafe ? null : params.deloadRirMin;

  if (last == null) {
    return ExerciseTarget(
      exerciseId: spec.id,
      action: ProgressionAction.start,
      loadKg: null,
      repTarget: spec.timed ? spec.repMin : params.baselineRepMax,
      stallCount: 0,
      previousBest: null,
      rirTarget: rir,
      messageEs: spec.timed
          ? 'Primera vez: elige una carga que puedas sostener '
                '${spec.repMin}–${spec.repMax} s.'
          : 'Primera vez: busca la carga con la que el fallo técnico llegue '
                'entre la repetición ${params.baselineRepMin} y la '
                '${params.baselineRepMax}.',
    );
  }

  if (mode == SessionMode.deload) {
    final reps = (last.validReps - params.deloadRirMin).clamp(1, spec.repMax);
    return ExerciseTarget(
      exerciseId: spec.id,
      action: ProgressionAction.deload,
      loadKg: last.loadKg,
      repTarget: reps,
      stallCount: stalls,
      previousBest: best,
      rirTarget: params.deloadRirMin,
      messageEs:
          'Descarga: misma carga, termina con '
          '${params.deloadRirMin}–${params.deloadRirMax} repeticiones en '
          'reserva. Sin fallo.',
    );
  }

  if (mode == SessionMode.retest) {
    return ExerciseTarget(
      exerciseId: spec.id,
      action: ProgressionAction.retest,
      loadKg: last.loadKg,
      repTarget: (last.validReps + 1).clamp(spec.repMin, spec.repMax),
      stallCount: stalls,
      previousBest: best,
      rirTarget: rir,
      messageEs:
          'Re-test tras la descarga: misma carga que la última sesión '
          'normal, intenta superarla.',
    );
  }

  final overshoot =
      last.validReps > spec.repMax + params.jumpRepsOverMax ||
      last.validReps > params.jumpRepsAbsolute;
  if (overshoot && !spec.assisted && !spec.timed && spec.minIncrementKg > 0) {
    final e1rm = epleyE1rm(last.loadKg, last.validReps)!;
    final raw = e1rm / (1 + params.jumpTargetReps / epleyDivisor);
    var load =
        (raw / spec.minIncrementKg).floorToDouble() * spec.minIncrementKg;
    if (load <= last.loadKg) load = last.loadKg + spec.minIncrementKg;
    return ExerciseTarget(
      exerciseId: spec.id,
      action: ProgressionAction.jump,
      loadKg: load,
      repTarget: spec.repMin,
      stallCount: stalls,
      previousBest: best,
      rirTarget: rir,
      messageEs:
          'Hiciste ${last.validReps} repeticiones: la carga se quedó corta. '
          'Salta a ${formatDecimal(load)} kg (tu 1RM estimado de '
          '${formatDecimal(e1rm)} kg da unas ${params.jumpTargetReps} '
          'repeticiones).',
    );
  }

  if (last.validReps >= spec.repMax) {
    final next = spec.assisted
        ? (last.loadKg - spec.minIncrementKg).clamp(0, double.infinity)
        : last.loadKg + spec.minIncrementKg;
    final load = _round(next.toDouble(), spec.minIncrementKg);
    return ExerciseTarget(
      exerciseId: spec.id,
      action: ProgressionAction.increase,
      loadKg: load,
      repTarget: spec.repMin,
      stallCount: stalls,
      previousBest: best,
      rirTarget: rir,
      messageEs: spec.assisted
          ? 'Llegaste a ${spec.repMax} $unit: baja la asistencia a '
                '${formatDecimal(load)} kg.'
          : 'Llegaste a ${spec.repMax} $unit: sube a ${formatDecimal(load)} kg.',
    );
  }

  final repTarget = (last.validReps + 1).clamp(spec.repMin, spec.repMax);
  return ExerciseTarget(
    exerciseId: spec.id,
    action: ProgressionAction.hold,
    loadKg: last.loadKg,
    repTarget: repTarget,
    stallCount: stalls,
    previousBest: best,
    rirTarget: rir,
    messageEs:
        'Misma carga (${formatDecimal(last.loadKg)} kg): busca '
        '$repTarget $unit válidas.',
  );
}

/// Plan for the next session.
class SessionPlan {
  const SessionPlan({
    required this.earliestDate,
    required this.latestDate,
    required this.template,
    required this.mode,
    required this.extraRestDays,
    required this.maxStall,
    required this.postponeSuggested,
    required this.reasonsEs,
  });

  final DateTime earliestDate;
  final DateTime latestDate;
  final TrainingTemplate template;
  final SessionMode mode;
  final int extraRestDays;
  final int maxStall;
  final bool postponeSuggested;
  final List<String> reasonsEs;

  bool isDue(DateTime today) => !dateOnly(today).isBefore(earliestDate);
}

/// Next session date, template and mode. [exercises] are the specs of all
/// exercises that may appear in the history.
SessionPlan planNextSession({
  required List<SessionRecord> history,
  required Iterable<ExerciseSpec> exercises,
  required DateTime today,
  required ProgressionParams params,
  ReadinessBand? readinessToday,
}) {
  final day = dateOnly(today);
  if (history.isEmpty) {
    return SessionPlan(
      earliestDate: day,
      latestDate: day,
      template: TrainingTemplate.baseline,
      mode: SessionMode.normal,
      extraRestDays: 0,
      maxStall: 0,
      postponeSuggested: readinessToday == ReadinessBand.rojo,
      reasonsEs: const [
        'Sin historial: sesión BASE con la plantilla A para encontrar tus '
            'cargas.',
      ],
    );
  }
  final sorted = _sorted(history);
  final last = sorted.last;
  final reasons = <String>[];

  var maxStall = 0;
  for (final spec in exercises) {
    final s = stallCount(spec, sorted);
    if (s > maxStall) maxStall = s;
  }

  SessionMode mode;
  var extra = 0;
  if (last.mode == SessionMode.deload) {
    var blockStart = last.date;
    for (var i = sorted.length - 1; i >= 0; i--) {
      if (sorted[i].mode != SessionMode.deload) break;
      blockStart = sorted[i].date;
    }
    if (daysBetween(blockStart, day) >= params.deloadDays) {
      mode = SessionMode.retest;
      reasons.add('Terminó la semana de descarga: toca RE-TEST.');
    } else {
      mode = SessionMode.deload;
      reasons.add('Semana de descarga en curso.');
    }
  } else if (maxStall >= params.stallDeloadThreshold) {
    mode = SessionMode.deload;
    reasons.add(
      '$maxStall retrocesos seguidos: empieza una semana de '
      'descarga (RIR ${params.deloadRirMin}–${params.deloadRirMax}, sin '
      'fallo).',
    );
  } else {
    mode = SessionMode.normal;
    if (maxStall >= params.stallRestThreshold) {
      extra = params.stallExtraRestDays;
      reasons.add('$maxStall retrocesos seguidos: +$extra días de descanso.');
    }
  }

  final template = switch (last.template) {
    TrainingTemplate.a => TrainingTemplate.b,
    TrainingTemplate.b => TrainingTemplate.a,
    TrainingTemplate.baseline => TrainingTemplate.b,
  };
  final earliest = addDays(last.date, params.restDaysMin + extra);
  final latest = addDays(last.date, params.restDaysMax + extra);
  final postpone =
      readinessToday == ReadinessBand.rojo && !day.isBefore(earliest);
  if (postpone) {
    reasons.add(
      'Preparación ROJA hoy: se sugiere posponer 24 h (no es '
      'obligatorio).',
    );
  }
  if (reasons.isEmpty) {
    reasons.add(
      'Descanso normal de ${params.restDaysMin}–'
      '${params.restDaysMax} días.',
    );
  }
  return SessionPlan(
    earliestDate: earliest,
    latestDate: latest,
    template: template,
    mode: mode,
    extraRestDays: extra,
    maxStall: maxStall,
    postponeSuggested: postpone,
    reasonsEs: List.unmodifiable(reasons),
  );
}

class WarmupSet {
  const WarmupSet({required this.loadKg, required this.reps});
  final double loadKg;
  final int reps;
}

/// Two ramp sets (50 % × 8, 75 % × 3 by default) rounded to the machine's
/// increment. Assisted and timed exercises get no ramp.
List<WarmupSet> warmupRamp({
  required ExerciseSpec spec,
  required double targetLoadKg,
  required ProgressionParams params,
}) {
  if (spec.assisted || spec.timed || targetLoadKg <= 0) return const [];
  return [
    WarmupSet(
      loadKg: _round(targetLoadKg * params.warmup1Pct, spec.minIncrementKg),
      reps: params.warmup1Reps,
    ),
    WarmupSet(
      loadKg: _round(targetLoadKg * params.warmup2Pct, spec.minIncrementKg),
      reps: params.warmup2Reps,
    ),
  ];
}
