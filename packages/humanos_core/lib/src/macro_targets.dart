/// Daily macronutrient targets.
///
/// Protein is `g/kg × weight`, with g/kg clamped to the configured floor and
/// ceiling. The per-meal minimum (0.4 g/kg over 4 meals) may push the plan
/// above the daily target; that overshoot is allowed up to the configured
/// tolerance and explained, otherwise protein is split evenly (v1 rule).
/// Fat takes a fixed share of energy and carbohydrates fill the rest.
library;

import 'assumptions.dart';
import 'format_es.dart';

class MacroParams {
  const MacroParams({
    required this.proteinGPerKg,
    required this.proteinGPerKgFloor,
    required this.proteinGPerKgCeiling,
    required this.minPerMealGPerKg,
    required this.mealsPerDay,
    required this.planTolerance,
    required this.fatKcalFraction,
  });

  factory MacroParams.fromAssumptions(Assumptions a) => MacroParams(
    proteinGPerKg: a[A.proteinGPerKg],
    proteinGPerKgFloor: a[A.proteinGPerKgFloor],
    proteinGPerKgCeiling: a[A.proteinGPerKgCeiling],
    minPerMealGPerKg: a[A.proteinMinPerMealGPerKg],
    mealsPerDay: a.integer(A.proteinMealsPerDay),
    planTolerance: a[A.proteinPlanTolerance],
    fatKcalFraction: a[A.fatKcalFraction],
  );

  final double proteinGPerKg;
  final double proteinGPerKgFloor;
  final double proteinGPerKgCeiling;
  final double minPerMealGPerKg;
  final int mealsPerDay;
  final double planTolerance;
  final double fatKcalFraction;
}

/// Energy (Atwater) factors used to split kcal between macros.
const double kcalPerGramProtein = 4;
const double kcalPerGramCarb = 4;
const double kcalPerGramFat = 9;

class MacroTargets {
  const MacroTargets({
    required this.kcal,
    required this.weightKg,
    required this.proteinGPerKgUsed,
    required this.proteinClamped,
    required this.proteinG,
    required this.proteinPerMealG,
    required this.proteinPlanG,
    required this.fatG,
    required this.carbG,
    required this.carbsFloored,
  });

  final double kcal;
  final double weightKg;
  final double proteinGPerKgUsed;

  /// The configured g/kg was outside [floor, ceiling] and was clamped.
  final bool proteinClamped;

  /// Daily protein target.
  final double proteinG;

  /// Protein planned per meal.
  final double proteinPerMealG;

  /// Protein the plan actually delivers (per meal × meals).
  final double proteinPlanG;
  final double fatG;
  final double carbG;

  /// Carbohydrates would have been negative and were set to zero.
  final bool carbsFloored;

  double get proteinExcessG => proteinPlanG - proteinG;

  double get proteinExcessPct =>
      proteinG == 0 ? 0 : (proteinPlanG / proteinG - 1) * 100;

  /// Explanation shown when the per-meal minimum inflates the plan. Never
  /// claims that 0.4 g/kg "activa" synthesis: the response is graded.
  String get explanationEs {
    if (proteinExcessG <= 0.5) return '';
    return 'El plan aporta ${formatWhole(proteinPlanG)} g frente a un objetivo '
        'de ${formatWhole(proteinG)} g (+${formatWhole(proteinExcessPct)} %). '
        'El exceso viene del mínimo por comida, que reparte la proteína del '
        'día. Total: ${formatDecimal(proteinPlanG / weightKg)} g/kg.';
  }
}

/// Computes the targets for [kcal] at [weightKg].
MacroTargets macroTargets({
  required double kcal,
  required double weightKg,
  required MacroParams params,
}) {
  if (weightKg <= 0) {
    throw ArgumentError.value(weightKg, 'weightKg', 'Debe ser mayor que 0');
  }
  final clampedPerKg = params.proteinGPerKg
      .clamp(params.proteinGPerKgFloor, params.proteinGPerKgCeiling)
      .toDouble();
  final protein = clampedPerKg * weightKg;
  final meals = params.mealsPerDay < 1 ? 1 : params.mealsPerDay;
  final even = protein / meals;
  final minimum = params.minPerMealGPerKg * weightKg;
  var perMeal = even > minimum ? even : minimum;
  if (perMeal * meals > protein * (1 + params.planTolerance)) {
    perMeal = even;
  }
  final plan = perMeal * meals;
  final fat = kcal * params.fatKcalFraction / kcalPerGramFat;
  final carbRaw =
      (kcal - plan * kcalPerGramProtein - fat * kcalPerGramFat) /
      kcalPerGramCarb;
  return MacroTargets(
    kcal: kcal,
    weightKg: weightKg,
    proteinGPerKgUsed: clampedPerKg,
    proteinClamped: clampedPerKg != params.proteinGPerKg,
    proteinG: protein,
    proteinPerMealG: perMeal,
    proteinPlanG: plan,
    fatG: fat,
    carbG: carbRaw < 0 ? 0 : carbRaw,
    carbsFloored: carbRaw < 0,
  );
}
