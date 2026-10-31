import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  final p = AttributeParams.fromAssumptions(Assumptions.defaults());
  final today = DateTime.utc(2026, 10, 12);

  test('FUERZA = Σ current e1RM / Σ baseline × 100', () {
    final a = computeAttributes(
      AttributeInputs(
        today: today,
        e1rmBaseline: const {1: 100, 2: 50},
        e1rmCurrent: const {1: 120, 2: 60},
      ),
      p,
    );
    expect(a[AttributeKind.fuerza], closeTo(120, 1e-9));
  });

  test('RESISTENCIA = shifts with hydration ≥ 80 %', () {
    final a = computeAttributes(
      AttributeInputs(
        today: today,
        shifts: [
          ShiftHydration(date: today, plannedL: 3, drankL: 2.5),
          ShiftHydration(date: addDays(today, -1), plannedL: 3, drankL: 1.5),
          ShiftHydration(date: addDays(today, -2), plannedL: 3, drankL: null),
          ShiftHydration(date: addDays(today, -40), plannedL: 3, drankL: 3),
        ],
      ),
      p,
    );
    expect(a[AttributeKind.resistencia], closeTo(50, 1e-9));
  });

  test('RECUPERACIÓN from sleep and RHR', () {
    final a = computeAttributes(
      AttributeInputs(
        today: today,
        sleepHoursLast7: const [8, 8, 6, 6],
        rhrRecentMean: 57,
        rhrBaselineMean: 55,
        rhrBaselineSd: 2,
      ),
      p,
    );
    // sleep 7/8 = 0.875; rhr 1 − 2/(2×2) = 0.5 → mean 0.6875
    expect(a[AttributeKind.recuperacion], closeTo(68.75, 1e-9));
  });

  test('DISCIPLINA from sober, screen limit and minimum days', () {
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
        ],
      ),
      p,
    );
    expect(
      a[AttributeKind.disciplina],
      closeTo((0.5 + 0.5 + 1) / 3 * 100, 1e-9),
    );
  });

  test('no data gives null, never zero', () {
    final a = computeAttributes(AttributeInputs(today: today), p);
    expect(a.values.every((v) => v == null), isTrue);
  });

  test('attributesUp lists real increases only', () {
    final up = attributesUp(
      {AttributeKind.fuerza: 100, AttributeKind.disciplina: 80},
      {AttributeKind.fuerza: 104, AttributeKind.disciplina: 79},
    );
    expect(up, [AttributeKind.fuerza]);
  });
}
