import 'package:humanos_core/src/assumptions.dart';
import 'package:humanos_core/src/confidence.dart';
import 'package:humanos_core/src/day.dart';
import 'package:humanos_core/src/hydration_plan.dart';
import 'package:test/test.dart';

void main() {
  final p = HydrationParams.fromAssumptions(Assumptions.defaults());
  final today = DateTime.utc(2026, 10, 18);
  SweatFeelEntry e(int back, SweatFeel f) =>
      SweatFeelEntry(date: addDays(today, -back), feel: f);

  test('base range is one cup every 15–20 min without sweat data', () {
    final plan = hydrationPlan(
      heatHours: 8,
      feelHistory: const [],
      today: today,
      params: p,
    );
    expect(plan.lPerHMin, closeTo(0.72, 1e-9));
    expect(plan.lPerHMax, closeTo(0.96, 1e-9));
    expect(plan.totalLMin, closeTo(5.76, 1e-9));
    expect(plan.totalLMax, closeTo(7.68, 1e-9));
    expect(plan.confidence, Confidence.baja);
    expect(plan.factor.daysUsed, 0);
    expect(plan.summaryEs, contains('5,8–7,7 L'));
  });

  test('sweat feel scales the range by the 7-day mean factor', () {
    final mucho = hydrationPlan(
      heatHours: 8,
      feelHistory: [e(0, SweatFeel.mucho), e(1, SweatFeel.mucho)],
      today: today,
      params: p,
    );
    expect(mucho.factor.factor, closeTo(1.2, 1e-9));
    expect(mucho.lPerHMax, closeTo(1.152, 1e-9));
    expect(mucho.highlightElectrolytes, isTrue);
    expect(mucho.confidence, Confidence.media);

    final mixed = hydrationPlan(
      heatHours: 8,
      feelHistory: [e(0, SweatFeel.poco), e(2, SweatFeel.normal)],
      today: today,
      params: p,
    );
    expect(mixed.factor.factor, closeTo(0.9, 1e-9));
    expect(mixed.highlightElectrolytes, isFalse);
  });

  test('entries outside the window and duplicates per day are ignored', () {
    final f = sweatFactor(
      [
        e(7, SweatFeel.mucho),
        e(1, SweatFeel.poco),
        SweatFeelEntry(
          date: addDays(today, -1).add(const Duration(hours: 5)),
          feel: SweatFeel.normal,
        ),
      ],
      today: today,
      params: p,
    );
    expect(f.daysUsed, 1);
    expect(f.factor, closeTo(1.0, 1e-9));
  });

  test('the hourly cap limits the range', () {
    final strong = HydrationParams.fromAssumptions(
      Assumptions.defaults().copyWith({A.sweatFeelMuchoFactor: 2.0}),
    );
    final plan = hydrationPlan(
      heatHours: 4,
      feelHistory: [e(0, SweatFeel.mucho)],
      today: today,
      params: strong,
    );
    expect(plan.lPerHMax, closeTo(1.42, 1e-9));
    expect(plan.capped, isTrue);
    expect(plan.basisEs, contains('tope'));
  });

  test('no heat hours means no range', () {
    final plan = hydrationPlan(
      heatHours: 0,
      feelHistory: const [],
      today: today,
      params: p,
    );
    expect(plan.hasHeat, isFalse);
    expect(plan.totalLMax, 0);
    expect(plan.summaryEs, contains('según tu sed'));
  });

  test('only two reminders: before the shift and at lunch', () {
    final plan = hydrationPlan(
      heatHours: 9,
      feelHistory: [e(0, SweatFeel.mucho)],
      today: today,
      params: p,
    );
    final reminders = hydrationReminders(
      shiftStartMin: parseClock('07:00'),
      lunchStartMin: parseClock('12:00'),
      plan: plan,
      params: p,
    );
    expect(reminders, hasLength(2));
    expect(reminders[0].kind, HydrationReminderKind.preShift);
    expect(reminders[0].minuteOfDay, parseClock('06:30'));
    expect(reminders[0].titleEs, 'LLENA EL TERMO');
    expect(reminders[0].bodyEs, contains(plan.rangeEs));
    expect(reminders[0].bodyEs, contains(electrolyteNoteEs));
    expect(reminders[1].kind, HydrationReminderKind.lunch);
    expect(reminders[1].minuteOfDay, parseClock('12:00'));
  });

  test('sweat feel codes round-trip', () {
    for (final f in SweatFeel.values) {
      expect(SweatFeel.parse(f.code), f);
    }
    expect(SweatFeel.parse('x'), isNull);
    expect(SweatFeel.parse(null), isNull);
  });
}
