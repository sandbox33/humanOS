import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/off_client.dart';
import 'package:humanos/data/text_fold.dart';
import 'package:humanos/telemetry/ble_hr_source.dart';

void main() {
  group('BLE heart rate measurement (0x2A37)', () {
    test('UINT8 and UINT16 formats', () {
      expect(parseHeartRateMeasurement([0x00, 72]), 72);
      expect(parseHeartRateMeasurement([0x01, 0x2C, 0x01]), 300);
    });

    test('short or empty packets are ignored', () {
      expect(parseHeartRateMeasurement([]), isNull);
      expect(parseHeartRateMeasurement([0x00]), isNull);
      expect(parseHeartRateMeasurement([0x01, 0x2C]), isNull);
    });
  });

  group('Open Food Facts answer', () {
    test('label values are kept, implausible ones become unknown', () {
      final product = parseOffProduct(
        '{"status":1,"product":{"code":"7861234567890","product_name":"Atún en agua",'
        '"brands":"Marca prueba","nova_group":3,'
        '"nutriments":{"energy-kcal_100g":116,"proteins_100g":"26,5","fat_100g":-3}}}',
        fromCache: false,
      )!;
      expect(product.name, 'Atún en agua');
      expect(product.kcal100g, 116);
      expect(product.protein100g, 26.5);
      expect(product.fat100g, isNull);
      expect(product.carb100g, isNull);
      expect(product.fromCache, isFalse);
    });

    test('unknown products return null', () {
      expect(parseOffProduct('{"status":0}'), isNull);
      expect(parseOffProduct('no es json'), isNull);
    });
  });

  test('search text folding ignores accents and case', () {
    expect(foldText('PLÁTANO Ñame'), 'platano name');
    expect(ftsQuery('plat mad'), '"plat"* "mad"*');
    expect(ftsQuery('  '), '');
  });
}
