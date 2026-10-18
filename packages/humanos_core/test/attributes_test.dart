import 'package:humanos_core/src/assumptions.dart';
import 'package:humanos_core/src/attributes.dart';
import 'package:humanos_core/src/day.dart';
import 'package:humanos_core/src/readiness.dart';
import 'package:test/test.dart';

void main() {
  final p = AttributeParams.fromAssumptions(Assumptions.defaults());
  final today = DateTime.utc(2026, 10, 12);

  test('missing inputs give null, never zero', () {
    final a = computeAttributes(AttributeInputs(today: today), p);
    expect(a.keys, AttributeKind.values);
    expect(a.values.every((v) => v == null), isTrue);
  });

  test('FUERZA = Σ current e1RM / Σ baseline × 100', () {
    final a = computeAttributes(
      AttributeInputs(
        today: today,
        e1rmBaseline: const {1: 100, 2: 50, 3: 40},
        e1rmCurrent: const {1: 120, 2: 60},
      ),
      p,
    );
    expect(a[AttributeKind.fuerza], closeTo(120, 1e-9));
  });

  test('RESISTENCIA = mean of shifts logged and reminders acknowledged', () {
    final a = computeAttributes(
      AttributeInputs(
        today: today,
        shiftDays: [
          ShiftDay(
            date: today,
            logged: true,
            remindersSent: 2,
            remindersAcked: 2,
          ),
          ShiftDay(
            date: addDays(today, -1),
            logged: false,
            remindersSent: 2,
            remindersAcked: 0,
          ),
          ShiftDay(
            date: addDays(today, -40),
            logged: true,
            remindersSent: 2,
            remindersAcked: 2,
          ),
        ],
      ),
      p,
    );
    // logged 1/2, acknowledged 2/4 → 50
    expect(a[AttributeKind.resistencia], closeTo(50, 1e-9));
  });

  test('RESISTENCIA without reminders uses only the logged share', () {
    final a = computeAttributes(
      AttributeInputs(
        today: today,
        shiftDays: [
          ShiftDay(date: today, logged: true),
          ShiftDay(date: addDays(today, -1), logged: true),
          ShiftDay(date: addDays(today, -2), logged: false),
          ShiftDay(date: addDays(today, -3), logged: true),
        ],
      ),
      p,
    );
    expect(a[AttributeKind.resistencia], closeTo(75, 1e-9));
  });

  test('NUTRICIÓN counts complete days hitting kcal ±10 % and protein', () {
    NutritionDay day(int back, double kcal, double protein) => NutritionDay(
      date: addDays(today, -back),
      kcal: kcal,
      kcalTarget: 2800,
      proteinG: protein,
      proteinTargetG: 120,
    );
    final a = computeAttributes(
      AttributeInputs(
        today: today,
        nutritionDays: [
          day(0, 2800, 125), // hit
          day(1, 2550, 110), // kcal −8.9 %, protein 91.7 % → hit
          day(2, 2400, 130), // kcal −14 % → miss
          day(3, 2900, 100), // protein 83 % → miss
          day(45, 2800, 120), // outside the window
        ],
      ),
      p,
    );
    expect(a[AttributeKind.nutricion], closeTo(50, 1e-9));
  });

  test('a day without targets never counts as a hit', () {
    expect(
      nutritionDayHit(
        NutritionDay(
          date: today,
          kcal: 0,
          kcalTarget: 0,
          proteinG: 0,
          proteinTargetG: 0,
        ),
        0.1,
      ),
      isFalse,
    );
  });

  test('RECUPERACIÓN from sleep and readiness bands', () {
    final a = computeAttributes(
      AttributeInputs(
        today: today,
        sleepHoursLast7: const [8, 8, 6, 6],
        readinessBands: {
          today: ReadinessBand.verde,
          addDays(today, -1): ReadinessBand.amarillo,
          addDays(today, -2): ReadinessBand.rojo,
          addDays(today, -3): ReadinessBand.verde,
          addDays(today, -90): ReadinessBand.rojo,
        },
      ),
      p,
    );
    // sleep 7/8 = 0.875; readiness (1 + 0.5 + 0 + 1) / 4 = 0.625 → 75
    expect(a[AttributeKind.recuperacion], closeTo(75, 1e-9));
  });

  test('DISCIPLINA from minimum days, sobriety and screen limit', () {
    final a = computeAttributes(
      AttributeInputs(
        today: today,
        screenLimitMinutes: 60,
        disciplineDays: [
          DisciplineDay(
            date: today,
            sober: true,
            screenMinutes: 50,
            minimumMet: true,
          ),
          DisciplineDay(
            date: addDays(today, -1),
            sober: false,
            screenMinutes: 90,
            minimumMet: true,
          ),
          DisciplineDay(date: addDays(today, -2)),
        ],
      ),
      p,
    );
    // minimum 2/2, sober 1/2, screen 1/2 → (1 + 0.5 + 0.5) / 3
    expect(a[AttributeKind.disciplina], closeTo(66.6667, 1e-3));
  });

  test('attributesUp lists only real increases', () {
    final up = attributesUp(
      {
        AttributeKind.fuerza: 100,
        AttributeKind.nutricion: 40,
        AttributeKind.disciplina: null,
      },
      {
        AttributeKind.fuerza: 102,
        AttributeKind.nutricion: 40.5,
        AttributeKind.disciplina: 80,
      },
    );
    expect(up, [AttributeKind.fuerza]);
  });

  test('codes round-trip and labels carry accents', () {
    for (final kind in AttributeKind.values) {
      expect(AttributeKind.parse(kind.code), kind);
    }
    expect(AttributeKind.nutricion.labelEs, 'NUTRICIÓN');
    expect(AttributeKind.parse('X'), isNull);
  });
}
