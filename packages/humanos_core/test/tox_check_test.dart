import 'package:humanos_core/src/assumptions.dart';
import 'package:humanos_core/src/tox_check.dart';
import 'package:test/test.dart';

void main() {
  final a = Assumptions.defaults();
  final dict = ToxDictionary(
    termToIds: {
      'sodium fluoride': ['sodium_fluoride'],
      'fluoruro de sodio': ['sodium_fluoride'],
      'methylparaben': ['methylparaben'],
      'propylparaben': ['propylparaben'],
      'glycerin': ['glycerin'],
      'glicerina': ['glycerin'],
      'carboximetilcelulosa': ['cmc'],
      'e466': ['cmc'],
      'dioxido de titanio': ['tio2_food', 'tio2_cosmetic'],
      'isobutylparaben': ['isobutylparaben'],
    },
    items: {
      'sodium_fluoride': const ToxItem(
        id: 'sodium_fluoride',
        nameEs: 'Fluoruro de sodio',
        level: ToxLevel.verde,
        rationaleEs: 'Previene caries.',
        evidenceRef: 'Reglamento (CE) 1223/2009, anexo III',
        scope: ToxScope.cosmetic,
        noteChildrenEs:
            'Menores de 6 años: cantidad del tamaño de un guisante y con '
            'supervisión.',
      ),
      'methylparaben': const ToxItem(
        id: 'methylparaben',
        nameEs: 'Metilparabeno',
        level: ToxLevel.verde,
        rationaleEs: 'Permitido.',
        evidenceRef: 'SCCS/1514/13',
        scope: ToxScope.cosmetic,
      ),
      'propylparaben': const ToxItem(
        id: 'propylparaben',
        nameEs: 'Propilparabeno',
        level: ToxLevel.ambar,
        rationaleEs:
            'Permitido con límite; señales endocrinas no concluyentes.',
        evidenceRef: 'SCCS/1514/13',
        scope: ToxScope.cosmetic,
      ),
      'glycerin': const ToxItem(
        id: 'glycerin',
        nameEs: 'Glicerina',
        level: ToxLevel.verde,
        rationaleEs: 'Segura en el uso habitual.',
        evidenceRef: 'EFSA 2017',
        scope: ToxScope.both,
      ),
      'cmc': const ToxItem(
        id: 'cmc',
        nameEs: 'Carboximetilcelulosa (E466)',
        level: ToxLevel.ambar,
        rationaleEs: 'Evidencia mayormente preclínica.',
        evidenceRef: 'Chassaing et al. 2015',
        scope: ToxScope.food,
      ),
      'tio2_food': const ToxItem(
        id: 'tio2_food',
        nameEs: 'Dióxido de titanio (E171)',
        level: ToxLevel.rojo,
        rationaleEs: 'Ya no autorizado como aditivo alimentario en la UE.',
        evidenceRef: 'Reglamento (UE) 2022/63',
        scope: ToxScope.food,
      ),
      'tio2_cosmetic': const ToxItem(
        id: 'tio2_cosmetic',
        nameEs: 'Dióxido de titanio',
        level: ToxLevel.verde,
        rationaleEs: 'Permitido en cosméticos con condiciones.',
        evidenceRef: 'Reglamento (CE) 1223/2009, anexos IV y VI',
        scope: ToxScope.cosmetic,
      ),
      'isobutylparaben': const ToxItem(
        id: 'isobutylparaben',
        nameEs: 'Isobutilparabeno',
        level: ToxLevel.rojo,
        rationaleEs: 'Prohibido en cosméticos en la UE.',
        evidenceRef: 'Reglamento (UE) 358/2014',
        scope: ToxScope.cosmetic,
      ),
    },
  );

  ToxScanResult scan(String text, ProductKind kind) =>
      toxCheck(text, kind: kind, dictionary: dict, assumptions: a);

  test('splits on commas, parentheses and line breaks', () {
    expect(
      splitIngredients(
        'Ingredientes: Glicerina, conservante (metil-\nparaben), '
        'AGUA 70 %; E466*.',
      ),
      ['glicerina', 'metilparaben', 'e466'],
    );
  });

  test('toothpaste with 1450 ppm fluoride is VERDE with the children note', () {
    final r = scan(
      'Ingredients: Sorbitol, Glycerin, Sodium Fluoride (1450 ppm F)',
      ProductKind.oralCare,
    );
    final fluoride = r.ingredients.firstWhere(
      (i) => i.item?.isFluoride ?? false,
    );
    expect(fluoride.level, ToxLevel.verde);
    expect(fluoride.noteEs, contains('1450 ppm'));
    expect(fluoride.noteEs, contains('Menores de 6 años'));
    expect(r.fluoridePpm, 1450);
    // sorbitol is not in this dictionary → the overall cannot be VERDE.
    expect(r.overall, ToxLevel.gris);
    expect(r.unknownCount, 1);
  });

  test('fluoride above 1500 ppm becomes ÁMBAR', () {
    final r = scan('Glycerin, sodium fluoride 5000 ppm', ProductKind.oralCare);
    expect(r.overall, ToxLevel.ambar);
    expect(
      r.ingredients.firstWhere((i) => i.text.contains('fluoride')).noteEs,
      contains('5000 ppm'),
    );
  });

  test('an unknown ingredient is GRIS, never VERDE', () {
    final r = scan('Xilofenoato de algo', ProductKind.cosmetic);
    expect(r.ingredients.single.level, ToxLevel.gris);
    expect(r.overall, ToxLevel.gris);
    expect(r.summaryEs, contains('sin datos'));
  });

  test('all known and VERDE gives VERDE', () {
    final r = scan('Glycerin, Methylparaben', ProductKind.cosmetic);
    expect(r.overall, ToxLevel.verde);
  });

  test('propylparaben is ÁMBAR, banned parabens are ROJO', () {
    expect(
      scan('glycerin, propylparaben', ProductKind.cosmetic).overall,
      ToxLevel.ambar,
    );
    expect(
      scan('isobutylparaben', ProductKind.cosmetic).overall,
      ToxLevel.rojo,
    );
  });

  test('shared terms resolve by product type', () {
    expect(
      scan('dióxido de titanio', ProductKind.food).ingredients.single.item!.id,
      'tio2_food',
    );
    expect(
      scan('Dióxido de titanio', ProductKind.cosmetic).overall,
      ToxLevel.verde,
    );
  });

  test('food-only rows do not match cosmetics', () {
    expect(
      scan('carboximetilcelulosa', ProductKind.food).overall,
      ToxLevel.ambar,
    );
    expect(
      scan('carboximetilcelulosa', ProductKind.cosmetic).overall,
      ToxLevel.gris,
    );
  });

  test('an empty label explains what to do', () {
    final r = scan('   ', ProductKind.food);
    expect(r.ingredients, isEmpty);
    expect(r.summaryEs, contains('No se leyeron'));
  });

  test('ppm parsing and JSON for tox_scans', () {
    expect(parsePpm('flúor 1.450 ppm y 1000 ppm'), 1450);
    expect(parsePpm('sin flúor'), isNull);
    final json = scan('glycerin', ProductKind.cosmetic).toJson();
    expect(json['overall'], 'verde');
    expect(
      (json['ingredients']! as List).single,
      containsPair('tox_id', 'glycerin'),
    );
  });

  test('level codes round-trip', () {
    for (final l in ToxLevel.values) {
      expect(ToxLevel.parse(l.code), l);
    }
    expect(ToxLevel.parse('x'), ToxLevel.gris);
    expect(ToxScope.parse('food'), ToxScope.food);
  });
}
