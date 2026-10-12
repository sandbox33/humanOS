/// RPG-style attributes tied to real data (no variable rewards).
///
/// * FUERZA — Σ current e1RM / Σ baseline e1RM × 100 (same exercises).
/// * RESISTENCIA — % of shifts in the window with hydration ≥ 80 % of plan.
/// * RECUPERACIÓN — mean of a sleep score (7-night mean / target) and an
///   RHR score (1 at or below baseline, 0 at baseline + 2 SD).
/// * DISCIPLINA — mean of the sober rate, the screen-limit rate and the
///   minimum-day rate over days with data.
/// Missing inputs give null, never zero.
library;

import 'assumptions.dart';
import 'day.dart';

enum AttributeKind {
  fuerza('FUERZA'),
  resistencia('RESISTENCIA'),
  recuperacion('RECUPERACION'),
  disciplina('DISCIPLINA');

  const AttributeKind(this.code);
  final String code;

  String get labelEs =>
      this == AttributeKind.recuperacion ? 'RECUPERACIÓN' : code;
}

class ShiftHydration {
  const ShiftHydration({
    required this.date,
    required this.plannedL,
    required this.drankL,
  });

  final DateTime date;
  final double plannedL;
  final double? drankL;
}

class DisciplineDay {
  const DisciplineDay({
    required this.date,
    this.sober,
    this.screenMinutes,
    this.minimumMet,
  });

  final DateTime date;
  final bool? sober;
  final double? screenMinutes;
  final bool? minimumMet;
}

class AttributeParams {
  const AttributeParams({
    required this.windowDays,
    required this.hydrationGoal,
    required this.sleepTargetH,
    required this.rhrZeroSd,
  });

  factory AttributeParams.fromAssumptions(Assumptions a) => AttributeParams(
    windowDays: a.integer(A.attrWindowDays),
    hydrationGoal: a[A.hydrationGoalFraction],
    sleepTargetH: a[A.sleepTargetH],
    rhrZeroSd: a[A.attrRhrZeroSd],
  );

  final int windowDays;
  final double hydrationGoal;
  final double sleepTargetH;
  final double rhrZeroSd;
}

class AttributeInputs {
  const AttributeInputs({
    required this.today,
    this.e1rmCurrent = const {},
    this.e1rmBaseline = const {},
    this.shifts = const [],
    this.sleepHoursLast7 = const [],
    this.rhrRecentMean,
    this.rhrBaselineMean,
    this.rhrBaselineSd,
    this.disciplineDays = const [],
    this.screenLimitMinutes,
  });

  final DateTime today;
  final Map<int, double> e1rmCurrent;
  final Map<int, double> e1rmBaseline;
  final List<ShiftHydration> shifts;
  final List<double> sleepHoursLast7;
  final double? rhrRecentMean;
  final double? rhrBaselineMean;
  final double? rhrBaselineSd;
  final List<DisciplineDay> disciplineDays;
  final double? screenLimitMinutes;
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Computes the four attributes (0–100 scale; FUERZA can exceed 100).
Map<AttributeKind, double?> computeAttributes(
  AttributeInputs input,
  AttributeParams params,
) {
  final windowStart = addDays(input.today, -(params.windowDays - 1));
  bool inWindow(DateTime d) =>
      !dateOnly(d).isBefore(windowStart) &&
      !dateOnly(d).isAfter(dateOnly(input.today));

  double? fuerza;
  var current = 0.0, baseline = 0.0;
  for (final e in input.e1rmBaseline.entries) {
    final now = input.e1rmCurrent[e.key];
    if (now == null || e.value <= 0) continue;
    current += now;
    baseline += e.value;
  }
  if (baseline > 0) fuerza = current / baseline * 100;

  double? resistencia;
  final shifts = input.shifts
      .where((s) => inWindow(s.date) && s.plannedL > 0 && s.drankL != null)
      .toList();
  if (shifts.isNotEmpty) {
    final ok = shifts
        .where((s) => s.drankL! / s.plannedL >= params.hydrationGoal)
        .length;
    resistencia = ok / shifts.length * 100;
  }

  final recoveryParts = <double>[];
  if (input.sleepHoursLast7.isNotEmpty && params.sleepTargetH > 0) {
    final mean =
        input.sleepHoursLast7.reduce((a, b) => a + b) /
        input.sleepHoursLast7.length;
    recoveryParts.add(_clamp01(mean / params.sleepTargetH));
  }
  final recent = input.rhrRecentMean;
  final base = input.rhrBaselineMean;
  if (recent != null && base != null) {
    final sd = input.rhrBaselineSd ?? 0;
    if (recent <= base) {
      recoveryParts.add(1);
    } else if (sd <= 0) {
      recoveryParts.add(0);
    } else {
      recoveryParts.add(
        _clamp01(1 - (recent - base) / (params.rhrZeroSd * sd)),
      );
    }
  }
  final recuperacion = recoveryParts.isEmpty
      ? null
      : recoveryParts.reduce((a, b) => a + b) / recoveryParts.length * 100;

  final rates = <double>[];
  final days = input.disciplineDays.where((d) => inWindow(d.date)).toList();
  final soberDays = days.where((d) => d.sober != null).toList();
  if (soberDays.isNotEmpty) {
    rates.add(soberDays.where((d) => d.sober!).length / soberDays.length);
  }
  final limit = input.screenLimitMinutes;
  final screenDays = days.where((d) => d.screenMinutes != null).toList();
  if (limit != null && screenDays.isNotEmpty) {
    rates.add(
      screenDays.where((d) => d.screenMinutes! <= limit).length /
          screenDays.length,
    );
  }
  final minimumDays = days.where((d) => d.minimumMet != null).toList();
  if (minimumDays.isNotEmpty) {
    rates.add(
      minimumDays.where((d) => d.minimumMet!).length / minimumDays.length,
    );
  }
  final disciplina = rates.isEmpty
      ? null
      : rates.reduce((a, b) => a + b) / rates.length * 100;

  return {
    AttributeKind.fuerza: fuerza,
    AttributeKind.resistencia: resistencia,
    AttributeKind.recuperacion: recuperacion,
    AttributeKind.disciplina: disciplina,
  };
}

/// Attributes that went up by at least [minDelta] points compared with
/// [previous]. Feeds the (optional, ≤ 600 ms) feedback event.
List<AttributeKind> attributesUp(
  Map<AttributeKind, double?> previous,
  Map<AttributeKind, double?> current, {
  double minDelta = 1,
}) {
  final up = <AttributeKind>[];
  for (final kind in AttributeKind.values) {
    final before = previous[kind];
    final now = current[kind];
    if (before != null && now != null && now - before >= minDelta) {
      up.add(kind);
    }
  }
  return up;
}
