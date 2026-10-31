/// Meal schedule framed by the day's work window, and the day's energy
/// target.
///
/// Blocks around the window and its break: breakfast before work,
/// mid-morning, lunch (in the break), afternoon, post-workout (training
/// days, after work) and dinner. kcal weights come from the assumptions
/// and are normalised over the blocks of the day.
///
/// The energy target keeps v1's three distinct states: a registered workday
/// scales only the activity part by hours worked; an off day uses the
/// off-day factor; "no data" keeps the full workday target without
/// inventing a cut.
library;

import 'assumptions.dart';
import 'confidence.dart';
import 'day.dart';
import 'format_es.dart';
import 'interaction_rules.dart';

/// The work window that frames a day's meals.
class ShiftConfig {
  const ShiftConfig({
    required this.shiftStartMin,
    required this.shiftEndMin,
    required this.lunchStartMin,
    this.lunchMinutes,
  });

  /// Builds from `HH:MM` strings (a work template's clocks).
  factory ShiftConfig.fromClock({
    required String shiftStart,
    required String shiftEnd,
    required String lunchStart,
    int? lunchMinutes,
  }) => ShiftConfig(
    shiftStartMin: parseClock(shiftStart),
    shiftEndMin: parseClock(shiftEnd),
    lunchStartMin: parseClock(lunchStart),
    lunchMinutes: lunchMinutes,
  );

  final int shiftStartMin;
  final int shiftEndMin;
  final int lunchStartMin;

  /// Length of the work's own break; null falls back to the lunch-duration
  /// assumption.
  final int? lunchMinutes;

  /// Shift length in hours (wrapping past midnight).
  double get hours {
    var minutes = shiftEndMin - shiftStartMin;
    if (minutes <= 0) minutes += 1440;
    return minutes / 60;
  }
}

class ScheduleParams {
  const ScheduleParams({
    required this.breakfastBeforeShiftMin,
    required this.lunchDurationMin,
    required this.postworkoutAfterShiftMin,
    required this.dinnerAfterPostworkoutMin,
    required this.dinnerAfterShiftMin,
    required this.weights,
  });

  factory ScheduleParams.fromAssumptions(Assumptions a) => ScheduleParams(
    breakfastBeforeShiftMin: a.integer(A.breakfastBeforeShiftMin),
    lunchDurationMin: a.integer(A.lunchDurationMin),
    postworkoutAfterShiftMin: a.integer(A.postworkoutAfterShiftMin),
    dinnerAfterPostworkoutMin: a.integer(A.dinnerAfterPostworkoutMin),
    dinnerAfterShiftMin: a.integer(A.dinnerAfterShiftMin),
    weights: {
      MealBlock.breakfast: a[A.splitBreakfast],
      MealBlock.midMorning: a[A.splitMidMorning],
      MealBlock.lunch: a[A.splitLunch],
      MealBlock.afternoon: a[A.splitAfternoon],
      MealBlock.postWorkout: a[A.splitPostWorkout],
      MealBlock.dinner: a[A.splitDinner],
    },
  );

  final int breakfastBeforeShiftMin;
  final int lunchDurationMin;
  final int postworkoutAfterShiftMin;
  final int dinnerAfterPostworkoutMin;
  final int dinnerAfterShiftMin;
  final Map<MealBlock, double> weights;
}

class MealSlot {
  const MealSlot({
    required this.block,
    required this.minuteOfDay,
    required this.kcalShare,
    required this.contextEs,
  });

  final MealBlock block;
  final int minuteOfDay;

  /// Fraction of the day's kcal (all slots of a day sum to 1).
  final double kcalShare;
  final String contextEs;

  String get clock => formatClock(minuteOfDay);
}

/// Meal slots for a day, in chronological order.
List<MealSlot> mealSchedule({
  required ShiftConfig shift,
  required bool trainingDay,
  required bool workday,
  required ScheduleParams params,
}) {
  final lunchEnd =
      shift.lunchStartMin + (shift.lunchMinutes ?? params.lunchDurationMin);
  final postWorkout = shift.shiftEndMin + params.postworkoutAfterShiftMin;
  final dinner = trainingDay
      ? postWorkout + params.dinnerAfterPostworkoutMin
      : shift.shiftEndMin + params.dinnerAfterShiftMin;
  final raw = <(MealBlock, int, String)>[
    (
      MealBlock.breakfast,
      shift.shiftStartMin - params.breakfastBeforeShiftMin,
      workday ? 'Antes del trabajo' : 'Día libre — horario base',
    ),
    (
      MealBlock.midMorning,
      (shift.shiftStartMin + shift.lunchStartMin) ~/ 2,
      workday ? 'Durante el trabajo, antes de la pausa' : 'Día libre',
    ),
    (
      MealBlock.lunch,
      shift.lunchStartMin,
      workday ? 'En la pausa' : 'Día libre',
    ),
    (
      MealBlock.afternoon,
      (lunchEnd + shift.shiftEndMin) ~/ 2,
      workday ? 'Durante el trabajo, después de la pausa' : 'Día libre',
    ),
    if (trainingDay)
      (MealBlock.postWorkout, postWorkout, 'Después de entrenar'),
    (MealBlock.dinner, dinner, trainingDay ? 'Cena tras el entreno' : 'Cena'),
  ];
  final total = raw.fold(0.0, (s, r) => s + (params.weights[r.$1] ?? 0));
  final slots = [
    for (final r in raw)
      MealSlot(
        block: r.$1,
        minuteOfDay: r.$2,
        kcalShare: total == 0
            ? 1 / raw.length
            : (params.weights[r.$1] ?? 0) / total,
        contextEs: r.$3,
      ),
  ]..sort((a, b) => a.minuteOfDay.compareTo(b.minuteOfDay));
  return slots;
}

/// What is known about today's work.
enum DayType { workday, offDay, unknown }

class DayEnergy {
  const DayEnergy({
    required this.kcal,
    required this.dayType,
    required this.adjustmentKcal,
    required this.confidence,
    required this.noteEs,
    this.hoursWorked,
  });

  final int kcal;
  final DayType dayType;

  /// Difference from the full workday target (always an int).
  final int adjustmentKcal;
  final Confidence confidence;
  final String noteEs;
  final double? hoursWorked;
}

/// Bootstrap day target. [palWorkday]/[palOffday] and [surplusKcal] come
/// from the energy assumptions; [referenceHours] from the shift reference.
DayEnergy dailyEnergyTarget({
  required double bmr,
  required DayType dayType,
  required double palWorkday,
  required double palOffday,
  required double surplusKcal,
  required double referenceHours,
  double? hoursWorked,
}) {
  final full = bmr * palWorkday + surplusKcal;
  switch (dayType) {
    case DayType.unknown:
      return DayEnergy(
        kcal: full.round(),
        dayType: dayType,
        adjustmentKcal: 0,
        confidence: Confidence.baja,
        noteEs:
            'Sin trabajo registrado hoy: objetivo provisional de día de '
            'trabajo. Registra tu trabajo en TRABAJO para ajustarlo.',
      );
    case DayType.offDay:
      final value = bmr * palOffday + surplusKcal;
      return DayEnergy(
        kcal: value.round(),
        dayType: dayType,
        adjustmentKcal: (value - full).round(),
        confidence: Confidence.media,
        noteEs:
            'Día libre: sin trabajo, pero un día libre no es reposo '
            'absoluto. Si entrenas fuerte, come más que esto.',
      );
    case DayType.workday:
      final hours = hoursWorked ?? referenceHours;
      final activity = bmr * (palWorkday - 1);
      final ratio = referenceHours <= 0 ? 1.0 : hours / referenceHours;
      final value = bmr + activity * ratio + surplusKcal;
      return DayEnergy(
        kcal: value.round(),
        dayType: dayType,
        adjustmentKcal: (value - full).round(),
        confidence: Confidence.alta,
        hoursWorked: hours,
        noteEs:
            '${formatDecimal(hours)} h de trabajo frente a '
            '${formatWhole(referenceHours)} h de referencia. Solo se ajusta la '
            'parte de actividad; el gasto basal no cambia.',
      );
  }
}
