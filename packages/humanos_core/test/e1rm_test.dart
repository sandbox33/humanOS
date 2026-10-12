import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  test('Epley: load × (1 + reps / 30)', () {
    expect(epleyE1rm(100, 10), closeTo(133.333, 0.001));
    expect(epleyE1rm(100, 0), isNull);
  });

  test('e1RM PR', () {
    final pr = checkPr(
      loadKg: 105,
      reps: 9,
      previous: const [LiftResult(loadKg: 100, reps: 10)],
    );
    expect(pr.isE1rmPr, isTrue);
    expect(pr.previousBestE1rm, closeTo(133.333, 0.001));
  });

  test('reps-at-load PR counts heavier previous sets', () {
    final pr = checkPr(
      loadKg: 90,
      reps: 10,
      previous: const [LiftResult(loadKg: 100, reps: 10)],
    );
    expect(pr.isRepsAtLoadPr, isFalse);
    final pr2 = checkPr(
      loadKg: 100,
      reps: 11,
      previous: const [
        LiftResult(loadKg: 100, reps: 10),
        LiftResult(loadKg: 90, reps: 14),
      ],
    );
    expect(pr2.isRepsAtLoadPr, isTrue);
    expect(pr2.previousBestRepsAtLoad, 10);
  });

  test('first set ever is not a PR', () {
    final pr = checkPr(loadKg: 100, reps: 10, previous: const []);
    expect(pr.any, isFalse);
  });

  test('equal performance is not a PR', () {
    final pr = checkPr(
      loadKg: 100,
      reps: 10,
      previous: const [LiftResult(loadKg: 100, reps: 10)],
    );
    expect(pr.any, isFalse);
  });
}
