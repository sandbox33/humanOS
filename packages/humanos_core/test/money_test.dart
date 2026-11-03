import 'package:humanos_core/src/money.dart';
import 'package:test/test.dart';

void main() {
  test('parses Spanish and English decimal separators into cents', () {
    expect(parseCents('4,75'), 475);
    expect(parseCents('4.75'), 475);
    expect(parseCents('\$ 12'), 1200);
    expect(parseCents('12 USD'), 1200);
    expect(parseCents('0,5'), 50);
    expect(parseCents(',75'), 75);
    expect(parseCents('-0,40'), -40);
  });

  test('thousands separators and extra decimals', () {
    expect(parseCents('1.250,50'), 125050);
    expect(parseCents('1,250.50'), 125050);
    expect(parseCents('1.250.000'), 125000000);
    expect(parseCents('4,755'), 476);
    expect(parseCents('4,754'), 475);
  });

  test('rejects text that is not an amount', () {
    expect(parseCents(''), isNull);
    expect(parseCents('tres'), isNull);
    expect(parseCents('3,2,1a'), isNull);
  });

  test('formats cents for es-EC', () {
    expect(formatCents(475), '4,75 USD');
    expect(formatCents(5), '0,05 USD');
    expect(formatCents(-40), '-0,40 USD');
    expect(formatCents(125050, withCurrency: false), '1250,50');
  });

  test('rounds half away from zero', () {
    expect(divRound(5, 2), 3);
    expect(divRound(4, 3), 1);
    expect(divRound(-5, 2), -3);
    expect(divRound(7, -2), -4);
    expect(percentOfCents(999, 10), 100);
    expect(() => divRound(1, 0), throwsArgumentError);
  });
}
