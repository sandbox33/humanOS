import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  final p = InteractionParams.fromAssumptions(Assumptions.defaults());
  final noon = DateTime.utc(2026, 10, 12, 12);
  const lentils = NutrientItem(
    name: 'lentejas',
    grams: 250,
    ironMg: 8.3,
    vitaminCMg: 3.75,
    calciumMg: 47,
    fiberG: 19.8,
    fatG: 1.0,
    ironHeme: false,
  );
  const coffee = NutrientItem(
    name: 'café',
    grams: 200,
    ironMg: 0.02,
    vitaminCMg: 0,
    calciumMg: 4,
    fiberG: 0,
    fatG: 0.04,
    inhibitsNonHemeIron: true,
  );
  const broccoli = NutrientItem(
    name: 'brócoli',
    grams: 150,
    ironMg: 1.0,
    vitaminCMg: 97,
    calciumMg: 70,
    fiberG: 4.95,
    fatG: 0.6,
    ironHeme: false,
  );

  MealContext meal(
    List<NutrientItem> items, {
    MealBlock block = MealBlock.lunch,
    DateTime? at,
  }) => MealContext(block: block, at: at ?? noon, items: items);

  test('coffee with non-heme iron warns (media)', () {
    final r = checkInteractions(meal: meal([lentils, coffee]), params: p);
    expect(r.warnings.single.ruleId, 'polifenoles_hierro');
    expect(r.warnings.single.severity, WarningSeverity.media);
  });

  test('vitamin C mitigates in part, never neutralises', () {
    final r = checkInteractions(
      meal: meal([lentils, broccoli, coffee]),
      params: p,
    );
    final text = r.warnings.map((w) => w.messageEs).join(' ').toLowerCase();
    expect(text, contains('en parte'));
    expect(text.contains('neutraliz'), isFalse);
  });

  test('coffee within 90 min in another meal counts, beyond does not', () {
    final near = MealContext(
      block: MealBlock.midMorning,
      at: noon.subtract(const Duration(minutes: 60)),
      items: [coffee],
    );
    final far = MealContext(
      block: MealBlock.breakfast,
      at: noon.subtract(const Duration(minutes: 200)),
      items: [coffee],
    );
    expect(
      checkInteractions(
        meal: meal([lentils]),
        others: [near],
        params: p,
      ).warnings,
      isNotEmpty,
    );
    expect(
      checkInteractions(
        meal: meal([lentils]),
        others: [far],
        params: p,
      ).warnings,
      isEmpty,
    );
  });

  test('calcium with iron is a low-severity warning', () {
    const milk = NutrientItem(
      name: 'leche',
      grams: 300,
      ironMg: 0.1,
      calciumMg: 340,
      vitaminCMg: 0,
      fiberG: 0,
      fatG: 9.8,
    );
    final r = checkInteractions(meal: meal([lentils, milk]), params: p);
    expect(r.warnings.map((w) => w.ruleId), contains('calcio_hierro'));
  });

  test('raw fibre before the shift warns only on shift days', () {
    const rawSalad = NutrientItem(
      name: 'repollo crudo',
      grams: 400,
      fiberG: 10,
      ironMg: 1.9,
      vitaminCMg: 146,
      calciumMg: 160,
      fatG: 0.4,
      isRaw: true,
    );
    final breakfast = meal([rawSalad], block: MealBlock.breakfast);
    expect(
      checkInteractions(meal: breakfast, params: p).warnings.single.ruleId,
      'fibra_cruda_pre_turno',
    );
    expect(
      checkInteractions(meal: breakfast, params: p, shiftDay: false).warnings,
      isEmpty,
    );
  });

  test('heavy fat and user reflux triggers warn', () {
    const fried = NutrientItem(
      name: 'chicharrón',
      grams: 100,
      fatG: 30,
      ironMg: 1,
      vitaminCMg: 0,
      calciumMg: 10,
      fiberG: 0,
      triggersReflux: true,
    );
    final ids = checkInteractions(
      meal: meal([fried]),
      params: p,
    ).warnings.map((w) => w.ruleId);
    expect(ids, containsAll(['grasa_reflujo', 'reflujo_marcado']));
  });

  test('vitamin C with plant iron is reported as a synergy', () {
    final r = checkInteractions(meal: meal([lentils, broccoli]), params: p);
    expect(r.synergiesEs.single, contains('vitamina C'));
    expect(r.warnings, isEmpty);
  });

  test('missing nutrient data is reported, not assumed zero', () {
    const unknown = NutrientItem(name: 'jamaica', grams: 250);
    final r = checkInteractions(meal: meal([lentils, unknown]), params: p);
    expect(r.missingDataEs.first, contains('jamaica'));
  });
}
