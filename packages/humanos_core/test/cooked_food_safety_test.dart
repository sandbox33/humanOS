import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  final p = SafetyParams.fromAssumptions(Assumptions.defaults());
  final now = DateTime.utc(2026, 10, 12, 14);

  CookedBatchState at(double hours, {bool heat = false, bool fridge = false}) =>
      evaluateCookedBatch(
        name: 'arroz',
        cookedAt: now.subtract(Duration(minutes: (hours * 60).round())),
        now: now,
        heatExposed: heat,
        refrigerated: fridge,
        params: p,
      );

  test('three levels by hours at ambient temperature (v1 contract)', () {
    expect(
      [at(0.5).level, at(2.5).level, at(4.5).level],
      [SafetyLevel.ok, SafetyLevel.warn, SafetyLevel.discard],
    );
  });

  test('discard message says reheating does not remove the toxin', () {
    expect(at(5).messageEs, contains('Recalentar no elimina la toxina'));
  });

  test('heat exposure: discard at 1 h', () {
    expect(at(0.75, heat: true).level, SafetyLevel.warn);
    expect(at(1.0, heat: true).level, SafetyLevel.discard);
    expect(at(0.2, heat: true).level, SafetyLevel.ok);
  });

  test('refrigerated keeps normal storage for days', () {
    final s = at(30, fridge: true);
    expect(s.level, SafetyLevel.ok);
    expect(s.messageEs, contains('refrigerado'));
    expect(at(24 * 5, fridge: true).level, SafetyLevel.discard);
  });

  test('heat wins over the fridge flag', () {
    expect(at(1.5, heat: true, fridge: true).level, SafetyLevel.discard);
  });

  test('most urgent first', () {
    final sorted = sortByUrgency([at(0.5), at(4.5), at(2.5)]);
    expect(sorted.map((s) => s.level), [
      SafetyLevel.discard,
      SafetyLevel.warn,
      SafetyLevel.ok,
    ]);
  });

  test('hours left until the deadline', () {
    expect(at(1).hoursLeft(now), closeTo(3, 1e-6));
  });
}
