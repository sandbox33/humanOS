import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  final p = StreakParams.fromAssumptions(Assumptions.defaults());
  const e1 = HabitDef(
    id: 1,
    alias: 'P100',
    weight: 3,
    isMinimum: true,
    metric: HabitMetric.atLeast,
    target: 100,
  );
  const e2 = HabitDef(id: 2, alias: 'PESO', weight: 3, isMinimum: true);
  const e3 = HabitDef(id: 3, alias: 'CLARO', weight: 3, isMinimum: true);
  const secondary = HabitDef(
    id: 4,
    alias: 'LECTURA',
    weight: 1,
    isMinimum: false,
    metric: HabitMetric.atLeast,
    target: 20,
  );
  const screen = HabitDef(
    id: 5,
    alias: 'VISOR',
    weight: 1,
    isMinimum: false,
    metric: HabitMetric.atMost,
    target: 60,
  );
  final habits = [e1, e2, e3, secondary, screen];
  final today = DateTime.utc(2026, 10, 12);

  group('v1 contracts', () {
    test('a secondary failure does not erase the minimum day', () {
      final day = minimumDay(habits, {1: 120, 2: 1, 3: 1, 4: 0}, p);
      expect(day.met, isTrue);
    });

    test('2 of 3 essentials are enough', () {
      expect(minimumDay(habits, {1: 120, 2: 1, 3: 0}, p).met, isTrue);
      expect(minimumDay(habits, {1: 50, 2: 1, 3: 0}, p).met, isFalse);
    });

    test('a day without records is not a failure', () {
      expect(minimumDay(habits, const {}, p).noData, isTrue);
      expect(scoreDay(habits, const {}, p).noData, isTrue);
    });

    test(
      '"at most" with tolerance falls off gradually (60 + 30 → 75 = 0.5)',
      () {
        final e = evaluateHabit(screen, 75, p);
        expect(e.fulfillment, closeTo(0.5, 1e-9));
        expect(e.completed, isFalse);
      },
    );

    test('"at least" is capped at 1.0: doing more never compensates', () {
      expect(evaluateHabit(secondary, 45, p).fulfillment, 1.0);
    });

    test('global day needs 70 %', () {
      final s = scoreDay(habits, {1: 120, 2: 1, 3: 1, 4: 0, 5: 120}, p);
      expect(s.fraction, closeTo(9 / 11, 1e-9));
      expect(s.fraction >= p.globalThreshold, isTrue);
    });

    test('two failed minimum days in a row suggest a minimum mission', () {
      expect(suggestMinimumMission(DayStatus.failed, DayStatus.failed), isTrue);
      expect(suggestMinimumMission(DayStatus.empty, DayStatus.failed), isFalse);
    });
  });

  Map<DateTime, DayStatus> statuses(List<DayStatus> fromOldest) => {
    for (var i = 0; i < fromOldest.length; i++)
      addDays(today, -(fromOldest.length - 1 - i)): fromOldest[i],
  };

  test('pending today does not break the streak', () {
    final s = computeStreak(
      statuses([DayStatus.completed, DayStatus.completed, DayStatus.pending]),
      today: today,
      params: p,
    );
    expect(s.current, 2);
  });

  test('a failure breaks the streak but keeps best', () {
    final s = computeStreak(
      statuses([
        DayStatus.completed,
        DayStatus.completed,
        DayStatus.completed,
        DayStatus.failed,
        DayStatus.completed,
      ]),
      today: today,
      params: p,
    );
    expect(s.current, 1);
    expect(s.best, 3);
    expect(s.completedLast30, 4);
    expect(s.daysWithDataLast30, 5);
  });

  test('an empty day stops the count but is not counted as failure', () {
    final s = computeStreak(
      statuses([DayStatus.completed, DayStatus.empty, DayStatus.completed]),
      today: today,
      params: p,
    );
    expect(s.current, 1);
    expect(s.daysWithDataLast30, 2);
  });

  test('every 14 completed days earn a repair token that bridges a gap', () {
    final s = computeStreak(
      statuses([
        for (var i = 0; i < 14; i++) DayStatus.completed,
        DayStatus.failed,
        DayStatus.completed,
      ]),
      today: today,
      params: p,
    );
    expect(s.repairsUsed, 1);
    expect(s.repairTokens, 0);
    expect(s.current, 15);
    expect(s.best, 15);
  });

  test('dayStatuses marks today without data as pending', () {
    final result = dayStatuses(
      kind: StreakKind.minimum,
      habits: habits,
      valuesByDay: {
        addDays(today, -1): {1: 120, 2: 1, 3: 1},
        today: const {},
      },
      today: today,
      params: p,
    );
    expect(result[today], DayStatus.pending);
    expect(result[addDays(today, -1)], DayStatus.completed);
  });

  test('per-habit statuses', () {
    final result = habitStatuses(
      habit: screen,
      values: {addDays(today, -1): 30, addDays(today, -2): 90, today: null},
      today: today,
      params: p,
    );
    expect(result[addDays(today, -1)], DayStatus.completed);
    expect(result[addDays(today, -2)], DayStatus.failed);
    expect(result[today], DayStatus.pending);
  });
}
