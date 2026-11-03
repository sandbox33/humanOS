import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

// An invented receipt.
const receipt = '''
COMERCIAL DE PRUEBA
RUC 0000000000001
FECHA 03/11/2026
ARROZ FLOR 2KG        3.10
2 X HUEVOS CUBETA     4,50
MANI TOSTADO 500 G    1.25
LECHE 1 LB            0,95
PLATANO              0.60 *
SUBTOTAL              10,40
IVA 0%                0.00
TOTAL                10.40
EFECTIVO             20.00
CAMBIO                9.60
''';

void main() {
  test(
    'product lines with amount and grams; taxes, change and payment skipped',
    () {
      final r = parseReceipt(receipt);
      expect(r.lines.map((l) => l.name), [
        'ARROZ FLOR',
        'HUEVOS CUBETA',
        'MANI TOSTADO',
        'LECHE',
        'PLATANO',
      ]);
      expect(r.lines.map((l) => l.amountCents), [310, 450, 125, 95, 60]);
      expect(r.lines[0].grams, 2000);
      expect(r.lines[2].grams, 500);
      expect(r.lines[3].grams, closeTo(gramsPerPound, 1e-9));
      expect(r.lines[1].grams, isNull);
      expect(r.totalCents, 1040);
      expect(r.linesCents, 1040);
    },
  );

  test(
    'lines without a readable amount are left to the user; no total stays unknown',
    () {
      final r = parseReceipt('PAN\nQUESO 2,3\nAGUA 0.50');
      expect(r.lines.single.name, 'AGUA');
      expect(r.totalCents, isNull);
      expect(parseReceipt('').lines, isEmpty);
    },
  );

  test(
    'a product is remembered by a key that ignores accents, case and spaces',
    () {
      expect(receiptKey('  Maní   Tostado '), receiptKey('MANI TOSTADO'));
    },
  );
}
