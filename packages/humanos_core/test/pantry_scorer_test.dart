import 'package:humanos_core/src/assumptions.dart';
import 'package:humanos_core/src/confidence.dart';
import 'package:humanos_core/src/pantry_scorer.dart';
import 'package:test/test.dart';

void main() {
  final p = ScorerParams.fromAssumptions(Assumptions.defaults());
  const gap = NutritionGap(kcal: 800, proteinG: 40);

  PantryCandidate item(
    String key, {
    double? kcal = 150,
    double? protein = 10,
    double? nrf = 20,
    double? price = 4,
    int? nova = 1,
    int? expiry = 10,
    bool excluded = false,
    double grams = 500,
    double? diaas,
  }) => PantryCandidate(
    key: key,
    name: key,
    gramsAvailable: grams,
    kcalPer100g: kcal,
    proteinPer100g: protein,
    nrf93Per100kcal: nrf,
    priceUsdPerKg: price,
    nova: nova,
    daysToExpiry: expiry,
    userExcluded: excluded,
    diaas: diaas,
    foodConfidence: Confidence.alta,
  );

  test('NOVA 4 is penalised by 0.25', () {
    final scored = scorePantry(
      [item('a', nova: 1), item('b', nova: 4)],
      gap: gap,
      params: p,
    );
    final a = scored.firstWhere((s) => s.candidate.key == 'a');
    final b = scored.firstWhere((s) => s.candidate.key == 'b');
    expect(a.score - b.score, closeTo(0.25, 1e-9));
    expect(scored.first.candidate.key, 'a');
  });

  test('user-excluded items drop by 1.0', () {
    final scored = scorePantry(
      [item('a'), item('b', excluded: true)],
      gap: gap,
      params: p,
    );
    expect(scored.last.candidate.key, 'b');
    expect(scored.first.score - scored.last.score, closeTo(1.0, 1e-9));
  });

  test('NULL inputs drop their term and lower confidence', () {
    final scored = scorePantry(
      [
        item('full', diaas: 1.0),
        item('partial', nrf: null, price: null, nova: null, expiry: null),
      ],
      gap: gap,
      params: p,
    );
    final full = scored.firstWhere((s) => s.candidate.key == 'full');
    final partial = scored.firstWhere((s) => s.candidate.key == 'partial');
    expect(partial.terms.where((t) => t.dropped).length, 3);
    expect(partial.confidence, Confidence.baja);
    expect(full.confidence, Confidence.alta);
    expect(
      partial.terms
          .firstWhere((t) => t.kind == ScoreTermKind.nrfPerUsd)
          .contribution,
      0,
    );
  });

  test('protein without DIAAS is used unadjusted but lowers confidence', () {
    final scored = scorePantry([item('x')], gap: gap, params: p);
    final term = scored.single.terms.firstWhere(
      (t) => t.kind == ScoreTermKind.protein,
    );
    expect(term.dropped, isFalse);
    expect(scored.single.confidence, Confidence.media);
    expect(scored.single.notesEs.join(), contains('DIAAS'));
  });

  test('DIAAS above 100 % is truncated', () {
    final scored = scorePantry([item('x', diaas: 1.2)], gap: gap, params: p);
    final term = scored.single.terms.firstWhere(
      (t) => t.kind == ScoreTermKind.protein,
    );
    expect(term.rawValue, closeTo(10 / 150 * 100, 1e-9));
  });

  test('expiring soon is promoted, expired is flagged and ranked last', () {
    final scored = scorePantry(
      [
        item('later', expiry: 30),
        item('soon', expiry: 1),
        item('gone', expiry: -2),
      ],
      gap: gap,
      params: p,
    );
    expect(scored.first.candidate.key, 'soon');
    expect(scored.last.candidate.key, 'gone');
    expect(scored.last.expired, isTrue);
    expect(scored.last.notesEs.join(), contains('Vencido'));
  });

  test('empty stock is not ranked', () {
    final scored = scorePantry([item('a', grams: 0)], gap: gap, params: p);
    expect(scored, isEmpty);
  });

  test('z-scores make cheaper nutrient density win', () {
    final scored = scorePantry(
      [item('cheap', price: 2), item('expensive', price: 12)],
      gap: gap,
      params: p,
    );
    expect(scored.first.candidate.key, 'cheap');
    expect(explainScore(scored.first), contains('Densidad nutricional'));
  });

  test('cost per 10 g of protein', () {
    // Eggs at 4,00 USD/kg with 12,6 g protein/100 g → 0,317 USD per 10 g.
    expect(
      costPer10gProtein(priceUsdPerKg: 4, proteinPer100g: 12.6),
      closeTo(0.3175, 1e-4),
    );
    expect(costPer10gProtein(priceUsdPerKg: null, proteinPer100g: 12), isNull);
    expect(costPer10gProtein(priceUsdPerKg: 3, proteinPer100g: 0), isNull);
  });
}
