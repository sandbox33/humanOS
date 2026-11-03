import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  final defaults = MacroParams.fromAssumptions(Assumptions.defaults());

  test('70 kg at 3000 kcal', () {
    final t = macroTargets(kcal: 3000, weightKg: 70, params: defaults);
    expect(t.proteinG, closeTo(140, 1e-9));
    expect(t.proteinPerMealG, closeTo(35, 1e-9));
    expect(t.proteinPlanG, closeTo(140, 1e-9));
    expect(t.fatG, closeTo(100, 1e-9));
    expect(t.carbG, closeTo((3000 - 140 * 4 - 900) / 4, 1e-9));
    expect(t.proteinClamped, isFalse);
    expect(t.explanationEs, isEmpty);
  });

  test('g/kg is clamped to [1.6, 2.2]', () {
    final high = MacroParams.fromAssumptions(
      Assumptions.defaults().copyWith({A.proteinGPerKg: 2.6}),
    );
    final t = macroTargets(kcal: 3000, weightKg: 70, params: high);
    expect(t.proteinGPerKgUsed, 2.2);
    expect(t.proteinClamped, isTrue);
    final low = MacroParams.fromAssumptions(
      Assumptions.defaults().copyWith({A.proteinGPerKg: 1.0}),
    );
    expect(
      macroTargets(kcal: 3000, weightKg: 70, params: low).proteinG,
      closeTo(1.6 * 70, 1e-9),
    );
  });

  test('per-meal minimum may overshoot within tolerance and is explained', () {
    final p = MacroParams.fromAssumptions(
      Assumptions.defaults().copyWith({
        A.proteinGPerKg: 1.6,
        A.proteinMealsPerDay: 4.5,
      }),
    );
    // 4.5 rounds to 5 meals: 5 × 28 = 140 > 112 × 1.15 → even split.
    final t = macroTargets(kcal: 3000, weightKg: 70, params: p);
    expect(t.proteinPlanG, closeTo(112, 1e-9));
    final p2 = MacroParams.fromAssumptions(
      Assumptions.defaults().copyWith({
        A.proteinGPerKg: 1.6,
        A.proteinMinPerMealGPerKg: 0.45,
      }),
    );
    // 4 × 31.5 = 126 ≤ 112 × 1.15 = 128.8 → minimum kept, overshoot shown.
    final t2 = macroTargets(kcal: 3000, weightKg: 70, params: p2);
    expect(t2.proteinPlanG, closeTo(126, 1e-9));
    expect(t2.proteinPlanG <= t2.proteinG * 1.15 + 1e-9, isTrue);
    expect(t2.explanationEs, isNotEmpty);
    expect(t2.explanationEs.contains('activa la síntesis'), isFalse);
  });

  test('carbs never go negative', () {
    final t = macroTargets(kcal: 600, weightKg: 70, params: defaults);
    expect(t.carbG, 0);
    expect(t.carbsFloored, isTrue);
  });

  test('rejects non-positive weight', () {
    expect(
      () => macroTargets(kcal: 3000, weightKg: 0, params: defaults),
      throwsArgumentError,
    );
  });
}
