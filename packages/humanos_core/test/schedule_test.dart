import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  final a = Assumptions.defaults();
  final p = ScheduleParams.fromAssumptions(a);
  // Invented work window for the tests.
  final shift = ShiftConfig.fromClock(
    shiftStart: '06:30',
    shiftEnd: '16:30',
    lunchStart: '11:30',
  );

  test('workday with training has six blocks in order', () {
    final slots = mealSchedule(
      shift: shift,
      trainingDay: true,
      workday: true,
      params: p,
    );
    expect(slots.map((s) => s.block), [
      MealBlock.breakfast,
      MealBlock.midMorning,
      MealBlock.lunch,
      MealBlock.afternoon,
      MealBlock.postWorkout,
      MealBlock.dinner,
    ]);
    expect(slots.map((s) => s.clock), [
      '05:45',
      '09:00',
      '11:30',
      '14:30',
      '18:00',
      '19:15',
    ]);
    expect(slots.fold(0.0, (s, x) => s + x.kcalShare), closeTo(1, 1e-9));
    expect(slots.first.contextEs, 'Antes del trabajo');
  });

  test('without training the post-workout share is redistributed', () {
    final slots = mealSchedule(
      shift: shift,
      trainingDay: false,
      workday: true,
      params: p,
    );
    expect(slots.any((s) => s.block == MealBlock.postWorkout), isFalse);
    expect(slots.fold(0.0, (s, x) => s + x.kcalShare), closeTo(1, 1e-9));
    expect(slots.last.clock, '19:00');
  });

  test("the work's own break replaces the lunch-duration assumption", () {
    final ownBreak = ShiftConfig.fromClock(
      shiftStart: '06:30',
      shiftEnd: '16:30',
      lunchStart: '11:30',
      lunchMinutes: 30,
    );
    final slots = mealSchedule(shift: ownBreak, trainingDay: false, workday: true, params: p);
    expect(slots.firstWhere((s) => s.block == MealBlock.afternoon).clock, '14:15');
  });

  test('shift length', () {
    expect(shift.hours, 10);
  });

  group('day energy keeps three distinct states (v1)', () {
    const bmr = 1600.0;
    DayEnergy target(DayType type, {double? hours}) => dailyEnergyTarget(
      bmr: bmr,
      dayType: type,
      palWorkday: a[A.palWorkday],
      palOffday: a[A.palOffday],
      surplusKcal: a[A.bootstrapSurplusKcal],
      referenceHours: a[A.referenceShiftHours],
      hoursWorked: hours,
    );

    final work = target(DayType.workday, hours: 10);
    final off = target(DayType.offDay);
    final unknown = target(DayType.unknown);

    test('states, notes and confidences differ', () {
      expect({work.dayType, off.dayType, unknown.dayType}.length, 3);
      expect(off.noteEs == unknown.noteEs, isFalse);
      expect(off.confidence == unknown.confidence, isFalse);
    });

    test('less work never means more energy', () {
      expect(work.kcal >= off.kcal, isTrue);
      expect(target(DayType.workday, hours: 6).kcal < work.kcal, isTrue);
    });

    test('no data does not invent a cut', () {
      expect(unknown.adjustmentKcal, 0);
      expect(unknown.kcal, (bmr * 1.9 + 300).round());
    });

    test('full workday equals Mifflin × 1.9 + 300', () {
      expect(work.kcal, (bmr * 1.9 + 300).round());
      expect(work.adjustmentKcal, 0);
    });
  });
}
