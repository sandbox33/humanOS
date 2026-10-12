import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  test('dateOnly truncates to UTC midnight', () {
    final d = dateOnly(DateTime(2026, 10, 12, 23, 59));
    expect(d, DateTime.utc(2026, 10, 12));
  });

  test('daysBetween and addDays are calendar based', () {
    final a = DateTime.utc(2026, 2, 27);
    expect(addDays(a, 2), DateTime.utc(2026, 3, 1));
    expect(daysBetween(a, DateTime.utc(2026, 3, 1)), 2);
    expect(daysBetween(DateTime.utc(2026, 3, 1), a), -2);
  });

  test('isoDate round-trips through parseIsoDate', () {
    final d = DateTime.utc(2001, 1, 5);
    expect(isoDate(d), '2001-01-05');
    expect(parseIsoDate('2001-01-05'), d);
  });

  test('parseIsoDate rejects bad and impossible dates', () {
    expect(() => parseIsoDate('2026-02-30'), throwsFormatException);
    expect(() => parseIsoDate('12/10/2026'), throwsFormatException);
  });

  test('clock parsing and formatting', () {
    expect(parseClock('07:00'), 420);
    expect(parseClock('17:30'), 1050);
    expect(formatClock(420 - 45), '06:15');
    expect(formatClock(1440 + 30), '00:30');
    expect(() => parseClock('25:00'), throwsFormatException);
  });
}
