import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  test('comma decimal separator', () {
    expect(formatDecimal(1.25, decimals: 2), '1,25');
    expect(formatDecimal(3.0), '3,0');
    expect(formatWhole(2999.6), '3000');
  });

  test('negative zero is printed without sign', () {
    expect(formatDecimal(-0.01, decimals: 1), '0,0');
  });

  test('hours and minutes', () {
    expect(formatHoursMinutes(320), '5 h 20 min');
    expect(formatHoursMinutes(45), '45 min');
    expect(formatHoursMinutes(480), '8 h');
  });
}
