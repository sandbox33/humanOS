/// RPG-style attributes tied to real data (no variable rewards).
///
/// * FUERZA — Σ current e1RM / Σ baseline e1RM × 100 (same exercises).
/// * RESISTENCIA — mean of the share of workdays with the shift logged
///   (effort or sweat) and the share of hydration reminders acknowledged.
/// * NUTRICIÓN — share of DÍA COMPLETO days whose kcal are within the
///   tolerance of the target and whose protein reaches the target minus
///   the tolerance.
/// * RECUPERACIÓN — mean of a sleep score (7-night mean / target) and a
///   readiness score (VERDE 1, AMARILLO ½, ROJO 0 over the window).
/// * DISCIPLINA — mean of the minimum-day rate, the sober rate and the
///   screen-limit rate over days with data.
/// Missing inputs give null, never zero.
library;

import 'assumptions.dart';
import 'day.dart';
import 'readiness.dart';

enum AttributeKind {
  fuerza('FUERZA', 'FUERZA'),
  resistencia('RESISTENCIA', 'RESISTENCIA'),
  nutricion('NUTRICION', 'NUTRICIÓN'),
  recuperacion('RECUPERACION', 'RECUPERACIÓN'),
  disciplina('DISCIPLINA', 'DISCIPLINA');

  const AttributeKind(this.code, this.labelEs);

  /// Code stored in `attributes.attr` and `xp_log.attr`.
  final String code;
  final String labelEs;

  static AttributeKind? parse(String? code) {
    for (final kind in AttributeKind.values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}

/// One workday: whether the shift was logged and the hydration reminders.
class ShiftDay {
  const ShiftDay({
    required this.date,
    required this.logged,
    this.remindersSent = 0,
    this.remindersAcked = 0,
  });

  final DateTime date;

  /// Effort or sweat feel was recorded for the shift.
  final bool logged;
  final int remindersSent;
  final int remindersAcked;
}

/// A DÍA COMPLETO day with its targets.
class NutritionDay {
  const NutritionDay({
    required this.date,
    required this.kcal,
    required this.kcalTarget,
    required this.proteinG,
    required this.proteinTargetG,
  });

  final DateTime date;
  final double kcal;
  final double kcalTarget;
  final double proteinG;
  final double proteinTargetG;
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
    required this.sleepTargetH,
    required this.nutritionTolerance,
  });

  factory AttributeParams.fromAssumptions(Assumptions a) => AttributeParams(
    windowDays: a.integer(A.attrWindowDays),
    sleepTargetH: a[A.sleepTargetH],
    nutritionTolerance: a[A.attrNutritionTolerance],
  );

  final int windowDays;
  final double sleepTargetH;
  final double nutritionTolerance;
}

class AttributeInputs {
  const AttributeInputs({
    required this.today,
    this.e1rmCurrent = const {},
    this.e1rmBaseline = const {},
    this.shiftDays = const [],
    this.nutritionDays = const [],
    this.sleepHoursLast7 = const [],
    this.readinessBands = const {},
    this.disciplineDays = const [],
    this.screenLimitMinutes,
  });

  final DateTime today;
  final Map<int, double> e1rmCurrent;
  final Map<int, double> e1rmBaseline;
  final List<ShiftDay> shiftDays;
  final List<NutritionDay> nutritionDays;
  final List<double> sleepHoursLast7;

  /// Readiness per day; only days with real data (not "sin datos").
  final Map<DateTime, ReadinessBand> readinessBands;
  final List<DisciplineDay> disciplineDays;
  final double? screenLimitMinutes;
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

double? _meanOrNull(List<double> values) => values.isEmpty
    ? null
    : values.reduce((a, b) => a + b) / values.length * 100;

/// Whether [day] hits both kcal (± tolerance) and protein (≥ target −
/// tolerance).
bool nutritionDayHit(NutritionDay day, double tolerance) {
  if (day.kcalTarget <= 0 || day.proteinTargetG <= 0) return false;
  final kcalOk =
      (day.kcal - day.kcalTarget).abs() <= tolerance * day.kcalTarget;
  final proteinOk = day.proteinG >= (1 - tolerance) * day.proteinTargetG;
  return kcalOk && proteinOk;
}

/// Readiness score of one band (VERDE 1, AMARILLO ½, ROJO 0).
double readinessScore(ReadinessBand band) => switch (band) {
  ReadinessBand.verde => 1,
  ReadinessBand.amarillo => 0.5,
  ReadinessBand.rojo => 0,
};

/// Computes the five attributes (0–100; FUERZA can exceed 100).
Map<AttributeKind, double?> computeAttributes(
  AttributeInputs input,
  AttributeParams params,
) {
  final windowStart = addDays(input.today, -(params.windowDays - 1));
  final end = dateOnly(input.today);
  bool inWindow(DateTime d) =>
      !dateOnly(d).isBefore(windowStart) && !dateOnly(d).isAfter(end);

  double? fuerza;
  var current = 0.0, baseline = 0.0;
  for (final e in input.e1rmBaseline.entries) {
    final now = input.e1rmCurrent[e.key];
    if (now == null || e.value <= 0) continue;
    current += now;
    baseline += e.value;
  }
  if (baseline > 0) fuerza = current / baseline * 100;

  final shiftRates = <double>[];
  final shifts = input.shiftDays.where((s) => inWindow(s.date)).toList();
  if (shifts.isNotEmpty) {
    shiftRates.add(shifts.where((s) => s.logged).length / shifts.length);
    final sent = shifts.fold<int>(0, (sum, s) => sum + s.remindersSent);
    final acked = shifts.fold<int>(0, (sum, s) => sum + s.remindersAcked);
    if (sent > 0) shiftRates.add(_clamp01(acked / sent));
  }
  final resistencia = _meanOrNull(shiftRates);

  final nutrition = input.nutritionDays.where((d) => inWindow(d.date)).toList();
  final nutricion = nutrition.isEmpty
      ? null
      : nutrition
                .where((d) => nutritionDayHit(d, params.nutritionTolerance))
                .length /
            nutrition.length *
            100;

  final recoveryParts = <double>[];
  if (input.sleepHoursLast7.isNotEmpty && params.sleepTargetH > 0) {
    final mean =
        input.sleepHoursLast7.reduce((a, b) => a + b) /
        input.sleepHoursLast7.length;
    recoveryParts.add(_clamp01(mean / params.sleepTargetH));
  }
  final bands = input.readinessBands.entries
      .where((e) => inWindow(e.key))
      .map((e) => readinessScore(e.value))
      .toList();
  if (bands.isNotEmpty) {
    recoveryParts.add(bands.reduce((a, b) => a + b) / bands.length);
  }
  final recuperacion = _meanOrNull(recoveryParts);

  final rates = <double>[];
  final days = input.disciplineDays.where((d) => inWindow(d.date)).toList();
  final minimumDays = days.where((d) => d.minimumMet != null).toList();
  if (minimumDays.isNotEmpty) {
    rates.add(
      minimumDays.where((d) => d.minimumMet!).length / minimumDays.length,
    );
  }
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
  final disciplina = _meanOrNull(rates);

  return {
    AttributeKind.fuerza: fuerza,
    AttributeKind.resistencia: resistencia,
    AttributeKind.nutricion: nutricion,
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
