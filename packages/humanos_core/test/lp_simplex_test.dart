import 'package:humanos_core/src/lp_simplex.dart';
import 'package:test/test.dart';

void main() {
  test('textbook LP optimum', () {
    // max 3x + 5y s.t. x ≤ 4, 2y ≤ 12, 3x + 2y ≤ 18 → (2, 6), value 36.
    final s = solveLp(
      objective: const [-3, -5],
      constraints: const [
        LinearConstraint([1, 0], ConstraintSense.le, 4),
        LinearConstraint([0, 2], ConstraintSense.le, 12),
        LinearConstraint([3, 2], ConstraintSense.le, 18),
      ],
    );
    expect(s.status, LpStatus.optimal);
    expect(s.values[0], closeTo(2, 1e-9));
    expect(s.values[1], closeTo(6, 1e-9));
    expect(s.objective, closeTo(-36, 1e-9));
  });

  test('infeasible and unbounded are detected', () {
    expect(
      solveLp(
        objective: const [1],
        constraints: const [
          LinearConstraint([1], ConstraintSense.ge, 5),
          LinearConstraint([1], ConstraintSense.le, 3),
        ],
      ).status,
      LpStatus.infeasible,
    );
    expect(
      solveLp(
        objective: const [-1],
        constraints: const [
          LinearConstraint([1], ConstraintSense.ge, 1),
        ],
      ).status,
      LpStatus.unbounded,
    );
  });

  test('equality constraints and negative right-hand sides', () {
    final s = solveLp(
      objective: const [1, 1],
      constraints: const [
        LinearConstraint([1, 1], ConstraintSense.eq, 10),
        LinearConstraint([-1, 0], ConstraintSense.le, -3),
      ],
    );
    expect(s.status, LpStatus.optimal);
    expect(s.values[0] + s.values[1], closeTo(10, 1e-9));
    expect(s.values[0], greaterThanOrEqualTo(3 - 1e-9));
  });

  const open = DietParams(
    maxEnergyShare: 1.0,
    fatMaxFrac: 1.0,
    kcalOvershootFrac: 0.1,
  );

  test('two-food diet with a known optimum', () {
    // A: 4 kcal/g, no protein, 0.002 USD/g. B: 1.5 kcal/g, 0.25 g/g,
    // 0.006 USD/g. Need 2400 kcal and 120 g protein → B = 480 g, A = 420 g.
    final plan = planDiet(
      foods: const [
        DietFood(
          key: 'A',
          name: 'A',
          maxGrams: 10000,
          costUsdPerG: 0.002,
          kcalPerG: 4,
          proteinPerG: 0,
          sodiumMgPerG: 0,
        ),
        DietFood(
          key: 'B',
          name: 'B',
          maxGrams: 10000,
          costUsdPerG: 0.006,
          kcalPerG: 1.5,
          proteinPerG: 0.25,
          sodiumMgPerG: 0,
        ),
      ],
      targets: const DietTargets(
        kcalMin: 2400,
        proteinMinG: 120,
        sodiumMaxMg: 2300,
      ),
      params: open,
    );
    expect(plan.status, DietStatus.optimal);
    expect(plan.gramsByKey['A'], closeTo(420, 1e-6));
    expect(plan.gramsByKey['B'], closeTo(480, 1e-6));
    expect(plan.costUsd, closeTo(3.72, 1e-6));
  });

  test('sodium limit binds and is named', () {
    final plan = planDiet(
      foods: const [
        DietFood(
          key: 'salty',
          name: 'Embutido',
          maxGrams: 2000,
          costUsdPerG: 0.001,
          kcalPerG: 3,
          proteinPerG: 0.2,
          sodiumMgPerG: 10,
        ),
      ],
      targets: const DietTargets(
        kcalMin: 2400,
        proteinMinG: 100,
        sodiumMaxMg: 2300,
      ),
      params: open,
    );
    expect(plan.status, DietStatus.infeasible);
    expect(plan.bindingEs.join(), contains('sodio'));
  });

  test('insufficient protein in stock is named', () {
    final plan = planDiet(
      foods: const [
        DietFood(
          key: 'rice',
          name: 'Arroz',
          maxGrams: 5000,
          costUsdPerG: 0.001,
          kcalPerG: 3.6,
          proteinPerG: 0.07,
          sodiumMgPerG: 0,
        ),
      ],
      targets: const DietTargets(
        kcalMin: 2000,
        proteinMinG: 500,
        sodiumMaxMg: 2300,
      ),
      params: open,
    );
    expect(plan.status, DietStatus.infeasible);
    expect(plan.bindingEs.single, startsWith('proteína'));
  });

  test('beverages are excluded and listed', () {
    final plan = planDiet(
      foods: const [
        DietFood(
          key: 'soda',
          name: 'Gaseosa',
          maxGrams: 2000,
          costUsdPerG: 0.0005,
          kcalPerG: 0.4,
          proteinPerG: 0,
          isBeverage: true,
        ),
        DietFood(
          key: 'mystery',
          name: 'Sin datos',
          maxGrams: 600,
          costUsdPerG: 0.001,
        ),
      ],
      targets: const DietTargets(
        kcalMin: 500,
        proteinMinG: 20,
        sodiumMaxMg: 2300,
      ),
      params: open,
    );
    expect(plan.status, DietStatus.noCandidates);
    expect(plan.excludedEs.length, 2);
    expect(plan.costUsd, isNull);
  });

  group('without prices the plan maximises the score', () {
    const foods = [
      DietFood(
        key: 'eggs',
        name: 'Huevos',
        maxGrams: 600,
        kcalPerG: 1.43,
        proteinPerG: 0.126,
        score: 1.2,
      ),
      DietFood(
        key: 'rice',
        name: 'Arroz',
        maxGrams: 1000,
        kcalPerG: 1.3,
        proteinPerG: 0.027,
        score: 0.4,
      ),
      DietFood(
        key: 'cookies',
        name: 'Galletas',
        maxGrams: 500,
        kcalPerG: 4.8,
        proteinPerG: 0.06,
        score: -0.8,
      ),
    ];
    const targets = DietTargets(
      kcalMin: 1000,
      proteinMinG: 60,
      sodiumMaxMg: 2300,
    );

    test('works with no prices entered and prefers high scores', () {
      final plan = planDiet(foods: foods, targets: targets, params: open);
      expect(plan.status, DietStatus.optimal);
      expect(plan.objective, DietObjective.score);
      expect(plan.costUsd, isNull);
      expect(plan.kcal, greaterThanOrEqualTo(1000 - 1e-6));
      expect(plan.kcal, lessThanOrEqualTo(1100 + 1e-6));
      expect(plan.proteinG, greaterThanOrEqualTo(60 - 1e-6));
      expect(plan.gramsByKey.containsKey('cookies'), isFalse);
      expect(plan.messageEs, contains('sin precios'));
    });

    test('one missing price drops cost for the whole plan', () {
      final mixed = [
        ...foods
            .take(2)
            .map(
              (f) => DietFood(
                key: f.key,
                name: f.name,
                maxGrams: f.maxGrams,
                kcalPerG: f.kcalPerG,
                proteinPerG: f.proteinPerG,
                score: f.score,
                costUsdPerG: 0.002,
              ),
            ),
        foods[2],
      ];
      final plan = planDiet(foods: mixed, targets: targets, params: open);
      expect(plan.objective, DietObjective.score);
    });

    test('the kcal margin is named when protein needs more energy', () {
      final plan = planDiet(
        foods: const [
          DietFood(
            key: 'rice',
            name: 'Arroz',
            maxGrams: 5000,
            kcalPerG: 1.3,
            proteinPerG: 0.027,
            score: 0.4,
          ),
          DietFood(
            key: 'potato',
            name: 'Papa',
            maxGrams: 5000,
            kcalPerG: 0.77,
            proteinPerG: 0.02,
            score: 0.5,
          ),
          DietFood(
            key: 'pasta',
            name: 'Fideo',
            maxGrams: 5000,
            kcalPerG: 1.58,
            proteinPerG: 0.058,
            score: 0.3,
          ),
        ],
        targets: targets,
        params: open,
      );
      expect(plan.status, DietStatus.infeasible);
      expect(plan.bindingEs.join(' '), contains('kcal'));
    });
  });

  test('energy share cap keeps one food under 35 %', () {
    final plan = planDiet(
      foods: const [
        DietFood(
          key: 'oil',
          name: 'Aceite',
          maxGrams: 1000,
          costUsdPerG: 0.002,
          kcalPerG: 8.8,
          proteinPerG: 0,
          sodiumMgPerG: 0,
          fatPerG: 1,
        ),
        DietFood(
          key: 'rice',
          name: 'Arroz',
          maxGrams: 2000,
          costUsdPerG: 0.0015,
          kcalPerG: 3.6,
          proteinPerG: 0.07,
          sodiumMgPerG: 0.05,
          fatPerG: 0.006,
        ),
        DietFood(
          key: 'beans',
          name: 'Caraotas',
          maxGrams: 2000,
          costUsdPerG: 0.003,
          kcalPerG: 3.4,
          proteinPerG: 0.21,
          sodiumMgPerG: 0.05,
          fatPerG: 0.015,
        ),
        DietFood(
          key: 'eggs',
          name: 'Huevos',
          maxGrams: 1000,
          costUsdPerG: 0.004,
          kcalPerG: 1.4,
          proteinPerG: 0.125,
          sodiumMgPerG: 1.4,
          fatPerG: 0.1,
        ),
      ],
      targets: const DietTargets(
        kcalMin: 2800,
        proteinMinG: 110,
        sodiumMaxMg: 2300,
      ),
      params: const DietParams(
        maxEnergyShare: 0.35,
        fatMaxFrac: 0.35,
        kcalOvershootFrac: 0.1,
      ),
    );
    expect(plan.status, DietStatus.optimal);
    for (final e in plan.gramsByKey.entries) {
      final kcalPerG = {
        'oil': 8.8,
        'rice': 3.6,
        'beans': 3.4,
        'eggs': 1.4,
      }[e.key]!;
      expect(e.value * kcalPerG, lessThanOrEqualTo(0.35 * 2800 + 1e-6));
    }
    expect(plan.kcal, greaterThanOrEqualTo(2800 - 1e-6));
    expect(plan.proteinG, greaterThanOrEqualTo(110 - 1e-6));
  });

  test('unknown sodium makes the total a floor', () {
    final plan = planDiet(
      foods: const [
        DietFood(
          key: 'x',
          name: 'X',
          maxGrams: 2000,
          costUsdPerG: 0.001,
          kcalPerG: 3,
          proteinPerG: 0.2,
        ),
      ],
      targets: const DietTargets(
        kcalMin: 900,
        proteinMinG: 50,
        sodiumMaxMg: 2300,
      ),
      params: open,
    );
    expect(plan.status, DietStatus.optimal);
    expect(plan.sodiumPartial, isTrue);
  });

  test('nothing needed when targets are already met', () {
    final plan = planDiet(
      foods: const [],
      targets: const DietTargets(kcalMin: 0, proteinMinG: 0, sodiumMaxMg: 2300),
      params: open,
    );
    expect(plan.status, DietStatus.nothingNeeded);
  });
}
