/// Food interaction warnings computed from nutrient amounts (v1 rules).
///
/// Output is warnings only: nothing here ever blocks logging a meal. A
/// system that forbids food over a modest interaction trains the user to
/// ignore it. Missing nutrient data is reported, not treated as zero, and
/// mitigations are described as partial ("en parte"), never as
/// neutralising.
library;

import 'assumptions.dart';
import 'format_es.dart';

/// Meal blocks stored in `meals.block`.
enum MealBlock {
  breakfast('BREAKFAST', 'DESAYUNO'),
  midMorning('MID_MORNING', 'MEDIA MAÑANA'),
  lunch('LUNCH', 'ALMUERZO'),
  afternoon('AFTERNOON', 'TARDE'),
  postWorkout('POST_WORKOUT', 'POST-ENTRENO'),
  dinner('DINNER', 'CENA');

  const MealBlock(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static MealBlock parse(String code) => MealBlock.values.firstWhere(
    (b) => b.code == code,
    orElse: () => MealBlock.lunch,
  );
}

/// One food in a meal with nutrient amounts for the eaten portion.
class NutrientItem {
  const NutrientItem({
    required this.name,
    required this.grams,
    this.ironMg,
    this.vitaminCMg,
    this.calciumMg,
    this.fiberG,
    this.fatG,
    this.ironHeme,
    this.inhibitsNonHemeIron = false,
    this.isRaw = false,
    this.triggersReflux = false,
  });

  final String name;
  final double grams;
  final double? ironMg;
  final double? vitaminCMg;
  final double? calciumMg;
  final double? fiberG;
  final double? fatG;

  /// True for meat/fish iron; null when unknown (treated as non-heme).
  final bool? ironHeme;

  /// Coffee, tea, cocoa, hibiscus: polyphenols that bind non-heme iron.
  final bool inhibitsNonHemeIron;
  final bool isRaw;

  /// The user flagged this food as a reflux trigger.
  final bool triggersReflux;
}

class MealContext {
  const MealContext({
    required this.block,
    required this.at,
    required this.items,
  });

  final MealBlock block;
  final DateTime at;
  final List<NutrientItem> items;
}

class InteractionParams {
  const InteractionParams({
    required this.ironRelevantMg,
    required this.vitcSynergyMg,
    required this.calciumInhibitorMg,
    required this.polyphenolWindowMin,
    required this.calciumWindowMin,
    required this.rawFiberPreshiftG,
    required this.heavyFatMealG,
  });

  factory InteractionParams.fromAssumptions(Assumptions a) => InteractionParams(
    ironRelevantMg: a[A.ironRelevantMg],
    vitcSynergyMg: a[A.vitcSynergyMg],
    calciumInhibitorMg: a[A.calciumInhibitorMg],
    polyphenolWindowMin: a[A.polyphenolWindowMin],
    calciumWindowMin: a[A.calciumWindowMin],
    rawFiberPreshiftG: a[A.rawFiberPreshiftG],
    heavyFatMealG: a[A.heavyFatMealG],
  );

  final double ironRelevantMg;
  final double vitcSynergyMg;
  final double calciumInhibitorMg;
  final double polyphenolWindowMin;
  final double calciumWindowMin;
  final double rawFiberPreshiftG;
  final double heavyFatMealG;
}

enum WarningSeverity { baja, media }

class InteractionWarning {
  const InteractionWarning({
    required this.ruleId,
    required this.severity,
    required this.messageEs,
  });

  final String ruleId;
  final WarningSeverity severity;
  final String messageEs;
}

class InteractionReport {
  const InteractionReport({
    required this.warnings,
    required this.synergiesEs,
    required this.missingDataEs,
  });

  final List<InteractionWarning> warnings;
  final List<String> synergiesEs;

  /// Nutrients without data per food: totals are floors, not exact.
  final List<String> missingDataEs;

  bool get isEmpty =>
      warnings.isEmpty && synergiesEs.isEmpty && missingDataEs.isEmpty;
}

double _sum(
  Iterable<NutrientItem> items,
  double? Function(NutrientItem) pick,
) => items.fold(0.0, (s, it) => s + (pick(it) ?? 0));

double _nonHemeIron(Iterable<NutrientItem> items) => items
    .where((it) => it.ironHeme != true)
    .fold(0.0, (s, it) => s + (it.ironMg ?? 0));

/// Checks [meal] against nearby meals ([others], any time). [shiftDay]
/// enables the pre-shift raw fibre rule.
InteractionReport checkInteractions({
  required MealContext meal,
  required InteractionParams params,
  List<MealContext> others = const [],
  bool shiftDay = true,
}) {
  final warnings = <InteractionWarning>[];
  final synergies = <String>[];
  final items = meal.items;

  Iterable<NutrientItem> within(double minutes) sync* {
    for (final other in others) {
      final gap = other.at.difference(meal.at).inMinutes.abs();
      if (gap <= minutes) yield* other.items;
    }
  }

  final nonHeme = _nonHemeIron(items);
  final vitC = _sum(items, (it) => it.vitaminCMg);
  final polyNearby = within(
    params.polyphenolWindowMin,
  ).any((it) => it.inhibitsNonHemeIron);
  final polyHere = items.any((it) => it.inhibitsNonHemeIron);
  final hasPolyphenols = polyHere || polyNearby;

  if (hasPolyphenols && nonHeme >= params.ironRelevantMg) {
    if (vitC >= params.vitcSynergyMg) {
      warnings.add(
        InteractionWarning(
          ruleId: 'polifenoles_hierro_compensado',
          severity: WarningSeverity.baja,
          messageEs:
              'Los polifenoles (café, té) reducen la absorción de los '
              '${formatDecimal(nonHeme)} mg de hierro vegetal, pero los '
              '${formatWhole(vitC)} mg de vitamina C lo compensan en parte.',
        ),
      );
    } else {
      warnings.add(
        InteractionWarning(
          ruleId: 'polifenoles_hierro',
          severity: WarningSeverity.media,
          messageEs:
              'Polifenoles (café, té) a menos de '
              '${formatWhole(params.polyphenolWindowMin)} min de '
              '${formatDecimal(nonHeme)} mg de hierro vegetal reducen su '
              'absorción. Sepáralos o añade algo con vitamina C.',
        ),
      );
    }
  }

  final calcium =
      _sum(items, (it) => it.calciumMg) +
      _sum(within(params.calciumWindowMin), (it) => it.calciumMg);
  if (calcium >= params.calciumInhibitorMg &&
      nonHeme >= params.ironRelevantMg) {
    warnings.add(
      InteractionWarning(
        ruleId: 'calcio_hierro',
        severity: WarningSeverity.baja,
        messageEs:
            '${formatWhole(calcium)} mg de calcio a menos de '
            '${formatWhole(params.calciumWindowMin)} min de '
            '${formatDecimal(nonHeme)} mg de hierro vegetal: compiten por '
            'absorberse. Efecto moderado.',
      ),
    );
  }

  final preShift =
      meal.block == MealBlock.breakfast || meal.block == MealBlock.midMorning;
  final rawFiber = _sum(items.where((it) => it.isRaw), (it) => it.fiberG);
  if (shiftDay && preShift && rawFiber >= params.rawFiberPreshiftG) {
    warnings.add(
      InteractionWarning(
        ruleId: 'fibra_cruda_pre_turno',
        severity: WarningSeverity.media,
        messageEs:
            '${formatDecimal(rawFiber)} g de fibra cruda antes del turno '
            'físico suele dar molestias digestivas. Mejor cocida o en la cena.',
      ),
    );
  }

  final fat = _sum(items, (it) => it.fatG);
  final triggers = items.where((it) => it.triggersReflux).toList();
  if (triggers.isNotEmpty) {
    warnings.add(
      InteractionWarning(
        ruleId: 'reflujo_marcado',
        severity: WarningSeverity.media,
        messageEs:
            'Marcaste ${triggers.map((t) => t.name).join(', ')} como '
            'desencadenante de reflujo.',
      ),
    );
  }
  if (fat >= params.heavyFatMealG) {
    warnings.add(
      InteractionWarning(
        ruleId: 'grasa_reflujo',
        severity: WarningSeverity.baja,
        messageEs:
            '${formatWhole(fat)} g de grasa en esta comida retrasan el '
            'vaciado gástrico y pueden empeorar el reflujo. Cantidad moderada: '
            'no hace falta evitarla del todo.',
      ),
    );
  }

  if (!hasPolyphenols &&
      nonHeme >= params.ironRelevantMg &&
      vitC >= params.vitcSynergyMg) {
    final sources = items
        .where((it) => (it.vitaminCMg ?? 0) >= params.vitcSynergyMg / 2)
        .map((it) => it.name)
        .join(', ');
    synergies.add(
      'Buena combinación: ${formatWhole(vitC)} mg de vitamina C'
      '${sources.isEmpty ? '' : ' ($sources)'} con '
      '${formatDecimal(nonHeme)} mg de hierro vegetal mejoran bastante su '
      'absorción.',
    );
  }
  final heme = items.any((it) => it.ironHeme == true && (it.ironMg ?? 0) > 0);
  if (heme && nonHeme >= params.ironRelevantMg) {
    synergies.add(
      'La carne o el pescado del plato mejora la absorción del '
      'hierro vegetal que lo acompaña.',
    );
  }

  final missing = <String>[];
  void report(String label, double? Function(NutrientItem) pick) {
    final names = [
      for (final it in items)
        if (pick(it) == null) it.name,
    ];
    if (names.isNotEmpty) {
      missing.add('$label: sin dato en ${names.join(', ')}');
    }
  }

  report('hierro', (it) => it.ironMg);
  report('vitamina C', (it) => it.vitaminCMg);
  report('calcio', (it) => it.calciumMg);
  report('fibra', (it) => it.fiberG);
  report('grasa', (it) => it.fatG);

  return InteractionReport(
    warnings: List.unmodifiable(warnings),
    synergiesEs: List.unmodifiable(synergies),
    missingDataEs: List.unmodifiable(missing),
  );
}
