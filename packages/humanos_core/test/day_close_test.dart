import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

// Invented days only.
DayClose day(int d, int mood, int energy, {int minutes = 0, bool? honest}) =>
    DayClose(
      date: DateTime(2026, 11, d),
      mood: mood,
      energy: energy,
      interactionMinutes: {1: minutes},
      honestyYes: honest,
    );

void main() {
  test('scale and totals', () {
    expect(validScale(1), isTrue);
    expect(validScale(5), isTrue);
    expect(validScale(0), isFalse);
    expect(validScale(6), isFalse);
    expect(
      DayClose(
        date: DateTime(2026, 11, 1),
        mood: 3,
        energy: 3,
        interactionMinutes: const {1: 30, 2: 15},
      ).totalInteractionMinutes,
      45,
    );
  });

  test('no trends before the minimum days', () {
    final closes = [for (var d = 1; d <= 13; d++) day(d, 3, 3)];
    expect(closeTrends(closes, minDays: 14, window: 30), isNull);
  });

  test(
    'trends say how many days they rest on; answers counted, unanswered apart',
    () {
      final closes = [
        for (var d = 1; d <= 14; d++)
          day(
            d,
            d.isEven ? 4 : 2,
            3,
            minutes: d.isEven ? 60 : 10,
            honest: d <= 3 ? true : (d <= 10 ? false : null),
          ),
      ];
      final t = closeTrends(closes, minDays: 14, window: 30)!;
      expect(t.days, 14);
      expect(t.moodMean, 3);
      expect(t.energyMean, 3);
      expect(t.interactionMeanMinutes, 35);
      expect(t.honestyYesDays, 3);
      expect(t.answeredDays, 10);
      expect(t.moodVsInteraction, closeTo(1, 1e-9));
      expect(t.energyVsInteraction, isNull, reason: 'energy did not vary');
    },
  );

  test('the window keeps only the latest days', () {
    final closes = [for (var d = 1; d <= 20; d++) day(d, d <= 10 ? 1 : 5, 3)];
    final t = closeTrends(closes, minDays: 7, window: 10)!;
    expect(t.days, 10);
    expect(t.moodMean, 5);
  });

  test('pearson and its plain words', () {
    expect(pearson([1, 2, 3], [2, 4, 6]), closeTo(1, 1e-9));
    expect(pearson([1, 2, 3], [6, 4, 2]), closeTo(-1, 1e-9));
    expect(pearson([1, 2], [1, 2]), isNull);
    expect(correlationEs(null), contains('sin dato'));
    expect(correlationEs(0.42), 'r = 0,42, suben juntas');
    expect(correlationEs(-0.3), 'r = -0,30, una sube cuando la otra baja');
  });
}
