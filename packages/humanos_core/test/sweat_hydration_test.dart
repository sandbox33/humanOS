import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  final p = SweatParams.fromAssumptions(Assumptions.defaults());

  test('sweat rate = (pre − post + fluids − urine) / hours', () {
    final r = evaluateSweatTest(
      const SweatTest(preKg: 66, postKg: 65, fluidsL: 2, urineL: 0.5, hours: 2),
      p,
    );
    expect(r.valid, isTrue);
    expect(r.rateLPerH, closeTo(1.25, 1e-9));
    expect(r.lossPct, closeTo(1 / 66 * 100, 1e-9));
    expect(r.warnLoss, isFalse);
  });

  test('warns above 2 % body mass loss', () {
    final r = evaluateSweatTest(
      const SweatTest(
        preKg: 65,
        postKg: 63.5,
        fluidsL: 0.5,
        urineL: 0,
        hours: 3,
      ),
      p,
    );
    expect(r.lossPct!, greaterThan(2));
    expect(r.warnLoss, isTrue);
    expect(r.messageEs, contains('%'));
  });

  test('invalid inputs explain themselves', () {
    expect(
      evaluateSweatTest(
        const SweatTest(preKg: 65, postKg: 65, fluidsL: 0, urineL: 0, hours: 0),
        p,
      ).valid,
      isFalse,
    );
    final r = evaluateSweatTest(
      const SweatTest(preKg: 65, postKg: 66, fluidsL: 0, urineL: 0, hours: 1),
      p,
    );
    expect(r.valid, isFalse);
    expect(r.messageEs, isNotEmpty);
  });

  test('plan with a test replaces 80–100 % of the rate', () {
    final plan = hydrationPlan(heatHours: 4, params: p, sweatRateLPerH: 1.0);
    expect(plan.basedOnTest, isTrue);
    expect(plan.lPerHMin, closeTo(0.8, 1e-9));
    expect(plan.lPerHMax, closeTo(1.0, 1e-9));
    expect(plan.totalLMax, closeTo(4.0, 1e-9));
    expect(plan.capped, isFalse);
  });

  test('plan is capped at 1.42 L/h', () {
    final plan = hydrationPlan(heatHours: 2, params: p, sweatRateLPerH: 2.0);
    expect(plan.lPerHMax, 1.42);
    expect(plan.lPerHMin, 1.42);
    expect(plan.capped, isTrue);
  });

  test('without a test: 0.24 L every 15–20 min', () {
    final plan = hydrationPlan(heatHours: 1, params: p);
    expect(plan.basedOnTest, isFalse);
    expect(plan.lPerHMax, closeTo(0.24 * 4, 1e-9));
    expect(plan.lPerHMin, closeTo(0.24 * 3, 1e-9));
    expect(plan.summaryEs, contains('cada 15–20 min'));
  });

  test('sodium = litres × 40 mmol/L × 23 mg', () {
    final plan = hydrationPlan(heatHours: 1, params: p, sweatRateLPerH: 1.0);
    expect(plan.sodiumMgPerL, 920);
    expect(plan.sodiumMgMax, closeTo(920, 1e-9));
    expect(
      HydrationPlan.saltGramsFor(920),
      closeTo(920 / 1000 / 0.39337, 0.01),
    );
  });

  test('potassium is never derived from sodium', () {
    final plan = hydrationPlan(heatHours: 3, params: p, sweatRateLPerH: 1.2);
    expect(
      plan.toMap().keys.any((k) => k.toLowerCase().contains('pota')),
      isFalse,
    );
    expect(
      plan.toMap().keys.any((k) => k.toLowerCase().startsWith('k')),
      isFalse,
    );
  });
}
