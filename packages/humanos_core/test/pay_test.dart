import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

// Invented amounts only.
PayWeek week(
  int day,
  int cents, {
  int normalH = 40,
  int overtimeH = 0,
  int? overtimeCents,
}) => PayWeek(
  paidOn: DateTime(2026, 10, day),
  amountCents: cents,
  normalMinutes: normalH * 60,
  overtimeMinutes: overtimeH * 60,
  overtimeCents: overtimeCents,
);

void main() {
  group('hour values', () {
    test('no pay with hours: sin dato', () {
      expect(hourValues(const []).method, RateMethod.none);
      expect(hourValues([week(3, 1000, normalH: 0)]).method, RateMethod.none);
    });

    test('the pay slip split is exact', () {
      final v = hourValues([
        week(10, 25000, normalH: 40, overtimeH: 5, overtimeCents: 5000),
      ]);
      expect(v.method, RateMethod.slip);
      expect(v.normalCentsPerHour, 500);
      expect(v.overtimeCentsPerHour, 1000);
      expect(v.averageCentsPerHour, divRound(25000 * 60, 45 * 60));
    });

    test(
      'weeks with different mixes give the split; the same mix only the average',
      () {
        // 5 USD per normal hour, 7,50 per overtime hour.
        final v = hourValues([
          week(3, 20000),
          week(10, 23750, overtimeH: 5),
          week(17, 27500, overtimeH: 10),
        ]);
        expect(v.method, RateMethod.estimated);
        expect(v.normalCentsPerHour, 500);
        expect(v.overtimeCentsPerHour, 750);

        final same = hourValues([
          week(3, 22000, overtimeH: 4),
          week(10, 22000, overtimeH: 4),
        ]);
        expect(same.method, RateMethod.average);
        expect(same.averageCentsPerHour, 500);
        expect(same.overtimeCentsPerHour, isNull);
      },
    );
  });

  group('cash', () {
    test('the last count minus what was spent after it plus pay after it', () {
      final counted = DateTime(2026, 11, 1, 20);
      final cash = cashNow(
        countedCents: 5000,
        countedAt: counted,
        spent: [
          (cents: 300, loggedAt: DateTime(2026, 11, 1, 12)), // before the count
          (cents: 450, loggedAt: DateTime(2026, 11, 2, 8)),
        ],
        pay: [
          week(31, 20000),
          PayWeek(
            paidOn: DateTime(2026, 11, 2, 18),
            amountCents: 10000,
            normalMinutes: 600,
            overtimeMinutes: 0,
          ),
        ],
      );
      expect(cash, 5000 - 450 + 10000);
    });

    test(
      'days the money lasts at the recent pace; today is not counted yet',
      () {
        final today = DateTime(2026, 11, 15);
        final expenses = [
          for (var d = 1; d <= 14; d++)
            Expense(
              date: DateTime(2026, 11, d),
              category: 'Prueba',
              amountCents: 500,
            ),
          Expense(date: today, category: 'Prueba', amountCents: 9999),
        ];
        final pace = dailySpendPace(expenses, today, days: 14);
        expect(pace, 500);
        expect(daysCovered(5000, pace), 10);
        expect(daysCovered(-10, pace), 0);
        expect(daysCovered(5000, null), isNull);
        expect(dailySpendPace(const [], today, days: 14), isNull);
      },
    );

    test('reaching the next income the user wrote down', () {
      final today = DateTime(2026, 11, 15);
      expect(
        reachesNextIncome(
          daysCovered: 10,
          today: today,
          nextIncome: DateTime(2026, 11, 20),
        ),
        isTrue,
      );
      expect(
        reachesNextIncome(
          daysCovered: 3,
          today: today,
          nextIncome: DateTime(2026, 11, 20),
        ),
        isFalse,
      );
      expect(
        reachesNextIncome(daysCovered: 3, today: today, nextIncome: null),
        isNull,
      );
      expect(
        reachesNextIncome(
          daysCovered: null,
          today: today,
          nextIncome: DateTime(2026, 11, 20),
        ),
        isNull,
      );
      expect(week(3, 100).asIncome.cents, 100);
    });
  });
}
