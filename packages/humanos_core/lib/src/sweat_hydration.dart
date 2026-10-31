/// Sweat test and the shift hydration/sodium plan.
///
/// Sweat rate = (pre − post + fluids − urine) / hours (1 kg ≈ 1 L). With a
/// test the plan replaces 80–100 % of that rate, capped per hour; without a
/// test it is a fixed 0.24 L every 15–20 min while in heat. Sodium to replace
/// = litres × sweat Na (mmol/L) × 23 mg/mmol. Potassium is deliberately not
/// derived from sodium: there is no physiological basis for a fixed ratio.
library;

import 'assumptions.dart';
import 'format_es.dart';

/// Milligrams of sodium per millimole (molar mass ≈ 23 g/mol).
const double sodiumMgPerMmol = 23;

/// Mass fraction of sodium in table salt (NaCl: 22.99 / 58.44).
const double sodiumFractionOfSalt = 22.99 / (22.99 + 35.45);

class SweatParams {
  const SweatParams({
    required this.replaceMinFrac,
    required this.replaceMaxFrac,
    required this.capLPerH,
    required this.bolusL,
    required this.bolusIntervalMinMin,
    required this.bolusIntervalMaxMin,
    required this.sweatNaMmolL,
    required this.lossWarnPct,
  });

  factory SweatParams.fromAssumptions(Assumptions a) => SweatParams(
    replaceMinFrac: a[A.sweatReplaceMinFrac],
    replaceMaxFrac: a[A.sweatReplaceMaxFrac],
    capLPerH: a[A.fluidCapLPerH],
    bolusL: a[A.heatBolusL],
    bolusIntervalMinMin: a[A.heatBolusIntervalMinMin],
    bolusIntervalMaxMin: a[A.heatBolusIntervalMaxMin],
    sweatNaMmolL: a[A.sweatNaMmolL],
    lossWarnPct: a[A.bodyMassLossWarnPct],
  );

  final double replaceMinFrac;
  final double replaceMaxFrac;
  final double capLPerH;
  final double bolusL;
  final double bolusIntervalMinMin;
  final double bolusIntervalMaxMin;
  final double sweatNaMmolL;
  final double lossWarnPct;
}

/// Inputs of a sweat test.
class SweatTest {
  const SweatTest({
    required this.preKg,
    required this.postKg,
    required this.fluidsL,
    required this.urineL,
    required this.hours,
  });

  final double preKg;
  final double postKg;
  final double fluidsL;
  final double urineL;
  final double hours;
}

class SweatTestResult {
  const SweatTestResult._({
    required this.valid,
    this.rateLPerH,
    this.netLossKg,
    this.lossPct,
    this.warnLoss = false,
    this.messageEs = '',
  });

  final bool valid;
  final double? rateLPerH;

  /// Body mass lost during the test (pre − post).
  final double? netLossKg;
  final double? lossPct;

  /// Loss above the warning threshold (default 2 % of body mass).
  final bool warnLoss;
  final String messageEs;
}

/// Evaluates a sweat test; invalid inputs return a Spanish explanation.
SweatTestResult evaluateSweatTest(SweatTest test, SweatParams params) {
  if (test.hours <= 0) {
    return const SweatTestResult._(
      valid: false,
      messageEs: 'Las horas de la prueba deben ser mayores que 0.',
    );
  }
  if (test.preKg <= 0 || test.postKg <= 0) {
    return const SweatTestResult._(
      valid: false,
      messageEs: 'Faltan los pesos antes y después.',
    );
  }
  if (test.fluidsL < 0 || test.urineL < 0) {
    return const SweatTestResult._(
      valid: false,
      messageEs: 'Líquidos y orina no pueden ser negativos.',
    );
  }
  final sweatL = test.preKg - test.postKg + test.fluidsL - test.urineL;
  final rate = sweatL / test.hours;
  if (rate <= 0) {
    return const SweatTestResult._(
      valid: false,
      messageEs:
          'La prueba da una pérdida nula o negativa: revisa los pesos y '
          'los líquidos anotados.',
    );
  }
  final netLoss = test.preKg - test.postKg;
  final lossPct = netLoss / test.preKg * 100;
  final warn = lossPct > params.lossWarnPct;
  return SweatTestResult._(
    valid: true,
    rateLPerH: rate,
    netLossKg: netLoss,
    lossPct: lossPct,
    warnLoss: warn,
    messageEs: warn
        ? 'Perdiste ${formatDecimal(lossPct)} % de tu peso en el turno '
              '(más de ${formatDecimal(params.lossWarnPct)} %): bebe más durante '
              'el turno.'
        : 'Tasa de sudor: ${formatDecimal(rate, decimals: 2)} L/h.',
  );
}

/// Plan for the thermos during the declared heat hours.
class HydrationPlan {
  const HydrationPlan({
    required this.basedOnTest,
    required this.heatHours,
    required this.lPerHMin,
    required this.lPerHMax,
    required this.capped,
    required this.sodiumMgPerL,
    this.bolusL,
    this.bolusIntervalMinMin,
    this.bolusIntervalMaxMin,
  });

  final bool basedOnTest;
  final double heatHours;
  final double lPerHMin;
  final double lPerHMax;

  /// The per-hour cap reduced the plan.
  final bool capped;

  /// Sodium per litre of sweat to replace (mmol/L × 23).
  final double sodiumMgPerL;
  final double? bolusL;
  final double? bolusIntervalMinMin;
  final double? bolusIntervalMaxMin;

  double get totalLMin => lPerHMin * heatHours;
  double get totalLMax => lPerHMax * heatHours;
  double get sodiumMgMin => totalLMin * sodiumMgPerL;
  double get sodiumMgMax => totalLMax * sodiumMgPerL;

  /// Grams of table salt that provide [sodiumMg].
  static double saltGramsFor(double sodiumMg) =>
      sodiumMg / 1000 / sodiumFractionOfSalt;

  /// Field map used by exports and tests. Contains no potassium entry.
  Map<String, Object?> toMap() => {
    'basedOnTest': basedOnTest,
    'heatHours': heatHours,
    'lPerHMin': lPerHMin,
    'lPerHMax': lPerHMax,
    'capped': capped,
    'sodiumMgPerL': sodiumMgPerL,
    'totalLMin': totalLMin,
    'totalLMax': totalLMax,
    'sodiumMgMin': sodiumMgMin,
    'sodiumMgMax': sodiumMgMax,
  };

  String get summaryEs {
    final litres = '${formatDecimal(totalLMin)}–${formatDecimal(totalLMax)} L';
    final sodium =
        '${formatWhole(sodiumMgMin)}–${formatWhole(sodiumMgMax)} mg de sodio';
    if (basedOnTest) {
      return 'Según tu prueba de sudor: ${formatDecimal(lPerHMin, decimals: 2)}'
          '–${formatDecimal(lPerHMax, decimals: 2)} L/h. Turno: $litres y '
          '$sodium.';
    }
    return 'Sin prueba de sudor: ${formatDecimal(bolusL ?? 0, decimals: 2)} L '
        'cada ${formatWhole(bolusIntervalMinMin ?? 0)}–'
        '${formatWhole(bolusIntervalMaxMin ?? 0)} min. Turno: $litres y $sodium.';
  }
}

/// Builds the plan for [heatHours] of heat exposure. [sweatRateLPerH] comes
/// from the latest valid sweat test; null means "no test yet".
HydrationPlan hydrationPlan({
  required double heatHours,
  required SweatParams params,
  double? sweatRateLPerH,
}) {
  final hours = heatHours < 0 ? 0.0 : heatHours;
  final naPerL = params.sweatNaMmolL * sodiumMgPerMmol;
  if (sweatRateLPerH != null && sweatRateLPerH > 0) {
    final rawMin = sweatRateLPerH * params.replaceMinFrac;
    final rawMax = sweatRateLPerH * params.replaceMaxFrac;
    final min = rawMin > params.capLPerH ? params.capLPerH : rawMin;
    final max = rawMax > params.capLPerH ? params.capLPerH : rawMax;
    return HydrationPlan(
      basedOnTest: true,
      heatHours: hours,
      lPerHMin: min,
      lPerHMax: max,
      capped: rawMax > params.capLPerH,
      sodiumMgPerL: naPerL,
    );
  }
  final rawMax = params.bolusL * 60 / params.bolusIntervalMinMin;
  final rawMin = params.bolusL * 60 / params.bolusIntervalMaxMin;
  final max = rawMax > params.capLPerH ? params.capLPerH : rawMax;
  final min = rawMin > params.capLPerH ? params.capLPerH : rawMin;
  return HydrationPlan(
    basedOnTest: false,
    heatHours: hours,
    lPerHMin: min,
    lPerHMax: max,
    capped: rawMax > params.capLPerH,
    sodiumMgPerL: naPerL,
    bolusL: params.bolusL,
    bolusIntervalMinMin: params.bolusIntervalMinMin,
    bolusIntervalMaxMin: params.bolusIntervalMaxMin,
  );
}
