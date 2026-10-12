import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  final p = ProgressionParams.fromAssumptions(Assumptions.defaults());
  const press = ExerciseSpec(
    id: 1,
    nameEs: 'Prensa',
    repMin: 8,
    repMax: 15,
    minIncrementKg: 5,
    failureSafe: true,
  );
  const dips = ExerciseSpec(
    id: 3,
    nameEs: 'Fondos asistidos',
    repMin: 6,
    repMax: 10,
    minIncrementKg: 5,
    failureSafe: true,
    assisted: true,
  );
  const rdl = ExerciseSpec(
    id: 5,
    nameEs: 'Peso muerto rumano',
    repMin: 6,
    repMax: 8,
    minIncrementKg: 2.5,
    failureSafe: false,
  );
  final start = DateTime.utc(2026, 9, 1);

  SessionRecord session(
    int day,
    double load,
    int reps, {
    ExerciseSpec spec = press,
    SessionMode mode = SessionMode.normal,
    ReadinessBand? band,
    bool overridden = false,
    TrainingTemplate template = TrainingTemplate.a,
  }) => SessionRecord(
    date: addDays(start, day),
    template: template,
    mode: mode,
    readiness: band,
    overridden: overridden,
    sets: [
      SetRecord(
        exerciseId: spec.id,
        loadKg: load * 0.5,
        reps: 8,
        validReps: 8,
        reachedFailure: false,
        isWarmup: true,
      ),
      SetRecord(
        exerciseId: spec.id,
        loadKg: load,
        reps: reps,
        validReps: reps,
        reachedFailure: true,
      ),
    ],
  );

  test('reaching rep_max adds the minimum increment', () {
    final t = nextExerciseTarget(
      press,
      [session(0, 100, 15)],
      mode: SessionMode.normal,
      params: p,
    );
    expect(t.action, ProgressionAction.increase);
    expect(t.loadKg, 105);
    expect(t.repTarget, 8);
  });

  test('below rep_max holds the load and asks for one more rep', () {
    final t = nextExerciseTarget(
      press,
      [session(0, 100, 11)],
      mode: SessionMode.normal,
      params: p,
    );
    expect(t.action, ProgressionAction.hold);
    expect(t.loadKg, 100);
    expect(t.repTarget, 12);
    expect(t.previousBest!.validReps, 11);
  });

  test('assisted machines progress by removing assistance', () {
    final t = nextExerciseTarget(
      dips,
      [session(0, 30, 10, spec: dips)],
      mode: SessionMode.normal,
      params: p,
    );
    expect(t.loadKg, 25);
  });

  test('no history starts with the baseline rep target', () {
    final t = nextExerciseTarget(
      press,
      const [],
      mode: SessionMode.normal,
      params: p,
    );
    expect(t.action, ProgressionAction.start);
    expect(t.loadKg, isNull);
    expect(t.messageEs, contains('8'));
  });

  test('RDL keeps reps in reserve, never to failure', () {
    final t = nextExerciseTarget(
      rdl,
      [session(0, 60, 7, spec: rdl)],
      mode: SessionMode.normal,
      params: p,
    );
    expect(t.rirTarget, 2);
  });

  test('two regressions add rest days', () {
    final history = [
      session(0, 100, 12),
      session(5, 100, 11),
      session(10, 100, 10),
    ];
    expect(stallCount(press, history), 2);
    final plan = planNextSession(
      history: history,
      exercises: [press],
      today: addDays(start, 11),
      params: p,
    );
    expect(plan.mode, SessionMode.normal);
    expect(plan.extraRestDays, 2);
    expect(plan.earliestDate, addDays(start, 10 + 4 + 2));
  });

  test('three regressions start a deload, then re-test', () {
    final history = [
      session(0, 100, 12),
      session(5, 100, 11),
      session(10, 100, 10),
      session(15, 100, 9),
    ];
    expect(stallCount(press, history), 3);
    final plan = planNextSession(
      history: history,
      exercises: [press],
      today: addDays(start, 16),
      params: p,
    );
    expect(plan.mode, SessionMode.deload);
    final deloadTarget = nextExerciseTarget(
      press,
      history,
      mode: SessionMode.deload,
      params: p,
    );
    expect(deloadTarget.rirTarget, 2);
    expect(deloadTarget.repTarget, 7);

    final afterDeload = [
      ...history,
      session(
        20,
        100,
        7,
        mode: SessionMode.deload,
        template: TrainingTemplate.b,
      ),
    ];
    final during = planNextSession(
      history: afterDeload,
      exercises: [press],
      today: addDays(start, 24),
      params: p,
    );
    expect(during.mode, SessionMode.deload);
    final after = planNextSession(
      history: afterDeload,
      exercises: [press],
      today: addDays(start, 27),
      params: p,
    );
    expect(after.mode, SessionMode.retest);
  });

  test('ROJO and overridden sessions are excluded from stall counting', () {
    final history = [
      session(0, 100, 12),
      session(5, 100, 9, band: ReadinessBand.rojo),
      session(10, 100, 8, overridden: true),
      session(15, 100, 12),
    ];
    expect(stallCount(press, history), 0);
  });

  test('a heavier load with fewer reps is not a regression', () {
    final history = [session(0, 100, 15), session(5, 105, 9)];
    expect(stallCount(press, history), 0);
  });

  test('stall counting restarts after a re-test', () {
    final history = [
      session(0, 100, 12),
      session(5, 100, 11),
      session(10, 100, 10, mode: SessionMode.retest),
      session(15, 100, 9),
    ];
    expect(stallCount(press, history), 1);
  });

  test('templates alternate and first session is BASELINE', () {
    final first = planNextSession(
      history: const [],
      exercises: [press],
      today: start,
      params: p,
    );
    expect(first.template, TrainingTemplate.baseline);
    final next = planNextSession(
      history: [session(0, 100, 10, template: TrainingTemplate.baseline)],
      exercises: [press],
      today: addDays(start, 1),
      params: p,
    );
    expect(next.template, TrainingTemplate.b);
    expect(next.earliestDate, addDays(start, 4));
    expect(next.latestDate, addDays(start, 5));
  });

  test('ROJO readiness suggests postponing but the plan stays', () {
    final plan = planNextSession(
      history: [session(0, 100, 10)],
      exercises: [press],
      today: addDays(start, 4),
      params: p,
      readinessToday: ReadinessBand.rojo,
    );
    expect(plan.postponeSuggested, isTrue);
    expect(plan.isDue(addDays(start, 4)), isTrue);
  });

  test('warm-up ramp: 50 % × 8 and 75 % × 3 rounded to the increment', () {
    final ramp = warmupRamp(spec: press, targetLoadKg: 120, params: p);
    expect(ramp.map((s) => s.loadKg), [60, 90]);
    expect(ramp.map((s) => s.reps), [8, 3]);
    expect(warmupRamp(spec: dips, targetLoadKg: 30, params: p), isEmpty);
  });
}
