import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/reference_models.dart';

import 'support/fixtures.dart';

void main() {
  final db = fixtureReferenceDb();

  List<String> titles(String query) => [for (final h in db.search(query)) h.title];

  test('"platano" finds "plátano" without the accent', () {
    expect(titles('platano'), containsAll(['Plátano verde', 'Plátano maduro']));
  });

  test('"cambur" finds banana and not plantain', () {
    final found = titles('cambur');
    expect(found, contains('Banano'));
    expect(found.where((t) => t.startsWith('Plátano')), isEmpty);
  });

  test('"caraota" finds black beans', () {
    expect(titles('caraota'), contains('Frijol negro cocido'));
  });

  test('prefix search per word and packaged products', () {
    expect(titles('plat mad'), ['Plátano maduro']);
    final hits = db.search('atun');
    expect(hits.single.kind, CatalogKind.product);
    expect(hits.single.barcode, '7861234567890');
  });

  test('recipes, exercises and templates come from the database', () {
    expect(db.recipe(1)!.totalGrams, 120);
    expect(db.exercises().map((e) => e.id), containsAll([1, 5]));
    expect(db.templates()['B'], [5]);
    expect(db.exercises().firstWhere((e) => e.id == 5).failureSafe, isFalse);
  });

  test('missing nutrients stay unknown', () {
    final profile = db.profile(1);
    expect(profile?.byFdcId.isEmpty ?? true, isTrue);
    expect(db.profile(4)!.byFdcId[1008], 132);
  });
}
