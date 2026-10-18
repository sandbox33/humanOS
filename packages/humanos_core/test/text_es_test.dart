import 'package:humanos_core/src/text_es.dart';
import 'package:test/test.dart';

void main() {
  test('folds diacritics like FTS5 remove_diacritics 2', () {
    expect(foldDiacritics('Plátano MADURO'), 'platano maduro');
    expect(foldDiacritics('Niño pingüino'), 'nino pinguino');
    expect(foldDiacritics('Façade Œuvre'), 'facade oeuvre');
  });

  test('normalises whitespace and line breaks', () {
    expect(
      normalizeEs('  Agua,\n  Glicerina\t(E422) '),
      'agua, glicerina (e422)',
    );
  });

  test('tokenises words and decimal numbers', () {
    expect(tokenizeEs('Comí 3 huevos y 1,5 tazas de café'), [
      'comi',
      '3',
      'huevos',
      'y',
      '1,5',
      'tazas',
      'de',
      'cafe',
    ]);
  });

  test('parses quantities from digits, fractions and words', () {
    expect(parseQuantityEs('3'), 3);
    expect(parseQuantityEs('1,5'), 1.5);
    expect(parseQuantityEs('2.25'), 2.25);
    expect(parseQuantityEs('1/2'), 0.5);
    expect(parseQuantityEs('1/0'), isNull);
    expect(parseQuantityEs('Tres'), 3);
    expect(parseQuantityEs('media'), 0.5);
    expect(parseQuantityEs('huevo'), isNull);
  });

  test('content tokens drop stopwords', () {
    expect(contentTokensEs('¿Cuánta proteína me falta hoy?'), [
      'proteina',
      'falta',
    ]);
  });

  test('pluralizes display units', () {
    expect(pluralizeEs('unidad', 1), 'unidad');
    expect(pluralizeEs('unidad', 3), 'unidades');
    expect(pluralizeEs('cucharada', 2), 'cucharadas');
    expect(pluralizeEs('cucharada', 0.5), 'cucharadas');
    expect(pluralizeEs('taza de arroz', 2), 'tazas de arroz');
    expect(pluralizeEs('lápiz', 2), 'lápices');
    expect(pluralizeEs('porción mediana', 2), 'porciones medianas');
  });
}
