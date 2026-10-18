import 'dart:math' as math;

import 'package:humanos_core/src/assumptions.dart';
import 'package:humanos_core/src/stress_context.dart';
import 'package:test/test.dart';

void main() {
  final p = StressParams.fromAssumptions(Assumptions.defaults());
  final day = DateTime(2026, 10, 18);

  List<HrSample> history({int hour = 19, double base = 75}) {
    final rng = math.Random(11);
    return [
      for (var d = 1; d <= 28; d++)
        for (var k = 0; k < 2; k++)
          HrSample(
            at: DateTime(2026, 10, 18 - d, hour, 10 + k * 20),
            bpm: base + rng.nextDouble() * 8 - 4,
          ),
    ];
  }

  StressContextCheck run(
    List<HrSample> samples, {
    bool capability = true,
    bool asked = false,
    List<TimeInterval> workouts = const [],
    bool Function(DateTime)? excluded,
  }) => checkStressContext(
    samples: samples,
    day: day,
    hrOutsideExercise: capability,
    workouts: workouts,
    isExcluded: excluded ?? (_) => false,
    alreadyAskedToday: asked,
    params: p,
  );

  final spike = HrSample(at: DateTime(2026, 10, 18, 19, 40), bpm: 112);

  test('an unusual reading outside work asks once, in neutral words', () {
    final r = run([...history(), spike]);
    expect(r.ask, isTrue);
    expect(r.zScore, greaterThan(2));
    expect(r.questionEs, contains('19:40'));
    expect(r.questionEs, contains('¿Qué estabas haciendo?'));
    expect(r.questionEs!.toLowerCase(), isNot(contains('estrés')));
  });

  test('off without the capability (e.g. Mi Fitness)', () {
    final r = run([...history(), spike], capability: false);
    expect(r.ask, isFalse);
    expect(r.reasonEs, contains('no comparte'));
  });

  test('at most once a day', () {
    expect(run([...history(), spike], asked: true).ask, isFalse);
  });

  test('workouts and the recovery margin are excluded', () {
    final workout = TimeInterval(
      DateTime(2026, 10, 18, 18, 30),
      DateTime(2026, 10, 18, 19, 15),
    );
    expect(run([...history(), spike], workouts: [workout]).ask, isFalse);
  });

  test('shift hours and the taller geofence are excluded', () {
    expect(
      run([...history(), spike], excluded: (t) => t.hour == 19).ask,
      isFalse,
    );
  });

  test('too few baseline samples for that hour: no question', () {
    final few = history().take(6).toList();
    expect(run([...few, spike]).ask, isFalse);
  });

  test('normal readings do not ask', () {
    final normal = HrSample(at: DateTime(2026, 10, 18, 19, 40), bpm: 77);
    expect(run([...history(), normal]).ask, isFalse);
  });

  test('baselines are per hour and skip workouts', () {
    final b = hourlyBaselines(
      history(),
      day: day,
      workouts: const [],
      params: p,
    );
    expect(b.keys, [19]);
    expect(b[19]!.n, 56);
    expect(b[19]!.mean, closeTo(75, 1.5));
    expect(StressContextAnswer.values.map((a) => a.code), [
      'taller',
      'gym',
      'trabajo',
      'conflicto',
      'otro',
    ]);
  });
}
