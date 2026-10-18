import 'package:humanos_core/src/portion_units.dart';
import 'package:test/test.dart';

void main() {
  const egg = PortionUnit(
    foodId: 1,
    unitEs: 'unidad',
    grams: 50,
    source: 'USDA FDC SR Legacy 01123, huevo grande',
  );
  const honey = PortionUnit(
    foodId: 2,
    unitEs: 'cucharada',
    grams: 21,
    source: 'USDA FDC SR Legacy 19296',
  );
  const plantain = [
    PortionUnit(foodId: 3, unitEs: 'unidad pequeña', grams: 150, source: 's'),
    PortionUnit(foodId: 3, unitEs: 'unidad mediana', grams: 200, source: 's'),
    PortionUnit(foodId: 3, unitEs: 'unidad grande', grams: 260, source: 's'),
  ];

  test('"comí 3 huevos" logs 150 g', () {
    final intake = parseTextIntake('Comí 3 huevos')!;
    expect(intake.quantity, 3);
    expect(intake.unit, isNull);
    expect(intake.foodQuery, 'huevos');
    final resolved = resolveIntake(intake, const [egg])!;
    expect(resolved.grams, 150);
    expect(resolved.unit, same(egg));
  });

  test('tablespoons, words and fractions', () {
    final miel = parseTextIntake('2 cdas de miel')!;
    expect(miel.unit, TypedUnit.tablespoon);
    expect(miel.foodQuery, 'miel');
    expect(resolveIntake(miel, const [honey])!.grams, 42);

    final media = parseTextIntake('me comí media arepa')!;
    expect(media.quantity, 0.5);
    expect(media.foodQuery, 'arepa');

    final dosYMedia = parseTextIntake('dos y media tazas de arroz')!;
    expect(dosYMedia.quantity, 2.5);
    expect(dosYMedia.unit, TypedUnit.cup);

    final docena = parseTextIntake('media docena de huevos')!;
    expect(docena.quantity, 6);
  });

  test('grams pass through without a unit table', () {
    final g = parseTextIntake('250 g de arroz')!;
    expect(g.isGrams, isTrue);
    expect(resolveIntake(g, const [])!.grams, 250);
    final glued = parseTextIntake('180g pollo')!;
    expect(glued.quantity, 180);
    expect(glued.isGrams, isTrue);
    expect(glued.foodQuery, 'pollo');
  });

  test('sizes pick the matching plantain unit', () {
    final big = parseTextIntake('un plátano grande')!;
    expect(big.unit, TypedUnit.large);
    expect(big.foodQuery, 'platano');
    expect(resolveIntake(big, plantain)!.grams, 260);
    final plain = parseTextIntake('1 plátano')!;
    expect(resolveIntake(plain, plantain)!.grams, 200);
  });

  test('never invents a weight', () {
    final cup = parseTextIntake('1 taza de miel')!;
    expect(resolveIntake(cup, const [honey]), isNull);
    expect(resolveIntake(parseTextIntake('3 huevos')!, const []), isNull);
    expect(parseTextIntake('comí'), isNull);
    expect(parseTextIntake('huevos'), isNull);
  });

  test('display uses the chosen unit with grams', () {
    expect(formatUnits(3, egg), '3 unidades (150 g)');
    expect(formatUnits(1, honey), '1 cucharada (21 g)');
    expect(formatUnits(0.5, egg), '½ unidad (25 g)');
    expect(formatUnits(1.5, honey), '1,5 cucharadas (32 g)');
    expect(gramsForUnits(0, egg), isNull);
  });

  test('a user-edited unit wins over the reference one', () {
    const mine = PortionUnit(
      foodId: 1,
      unitEs: 'unidad',
      grams: 60,
      source: 'Editado por ti',
      userEdited: true,
    );
    expect(preferredUnit(const [egg, mine]), same(mine));
    expect(preferredUnit(const [egg]), same(egg));
    expect(preferredUnit(const []), isNull);
  });
}
