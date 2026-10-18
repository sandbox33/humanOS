import 'package:humanos_core/src/assumptions.dart';
import 'package:humanos_core/src/interaction_rules.dart';
import 'package:humanos_core/src/schedule.dart';
import 'package:test/test.dart';

void main() {
  final a = Assumptions.defaults();
  final p = ScheduleParams.fromAssumptions(a);
  final shift = ShiftConfig.fromClock(
    shiftStart: '07:00',
    shiftEnd: '17:00',
    lunchStart: '12:00',
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
      '06:15',
      '09:30',
      '12:00',
      '15:00',
      '18:30',
      '19:45',
    ]);
    expect(slots.fold(0.0, (s, x) => s + x.kcalShare), closeTo(1, 1e-9));
    expect(slots.first.contextEs, 'Antes del turno');
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
    expect(slots.last.clock, '19:30');
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
      surplusKcal: a[A.surplusUnknownKcal],
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

  test('meals remaining uses exact counts, never "bastan"', () {
    final slots = mealSchedule(
      shift: ShiftConfig.fromClock(
        shiftStart: '07:00',
        shiftEnd: '17:00',
        lunchStart: '12:00',
      ),
      trainingDay: false,
      workday: true,
      params: ScheduleParams.fromAssumptions(Assumptions.defaults()),
    );
    expect(slots, hasLength(5));
    expect(mealsRemaining(slots, {}), 5);
    expect(mealsRemaining(slots, {MealBlock.breakfast, MealBlock.lunch}), 3);
    expect(mealsRemainingEs(3), 'Faltan 3 comidas');
    expect(mealsRemainingEs(1), 'Falta 1 comida');
    expect(mealsRemainingEs(0), 'Comidas del día registradas');
    expect(mealsRemainingEs(2).toLowerCase(), isNot(contains('bastan')));
  });
}
