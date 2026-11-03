import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  // 2026-10-30 is a Friday.
  final friday = DateTime(2026, 10, 30, 5, 0);
  final weekdays = daysMaskOf([1, 2, 3, 4, 5]);

  test('rings later today when the time has not passed', () {
    expect(
      nextAlarmAt(minuteOfDay: 5 * 60 + 30, daysMask: weekdays, now: friday),
      DateTime(2026, 10, 30, 5, 30),
    );
  });

  test('skips days off and the time already passed', () {
    final afterRing = DateTime(2026, 10, 30, 6, 0);
    expect(
      nextAlarmAt(minuteOfDay: 5 * 60 + 30, daysMask: weekdays, now: afterRing),
      DateTime(2026, 11, 2, 5, 30),
    );
  });

  test('exactly at the ring time means the next occurrence', () {
    final atRing = DateTime(2026, 10, 30, 5, 30);
    expect(
      nextAlarmAt(
        minuteOfDay: 5 * 60 + 30,
        daysMask: daysMaskOf([5]),
        now: atRing,
      ),
      DateTime(2026, 11, 6, 5, 30),
    );
  });

  test('no weekday means no ring; invalid times are refused', () {
    expect(nextAlarmAt(minuteOfDay: 300, daysMask: 0, now: friday), isNull);
    expect(
      () => nextAlarmAt(minuteOfDay: 1440, daysMask: weekdays, now: friday),
      throwsArgumentError,
    );
  });

  test('time left in Spanish', () {
    final now = DateTime(2026, 10, 30, 22, 0);
    expect(untilAlarmEs(DateTime(2026, 10, 31, 5, 30), now), 'en 7 h 30 min');
    expect(untilAlarmEs(DateTime(2026, 10, 30, 22, 45), now), 'en 45 min');
    expect(untilAlarmEs(DateTime(2026, 10, 31, 0, 0), now), 'en 2 h');
    expect(untilAlarmEs(now, now), 'en menos de 1 min');
  });
}
