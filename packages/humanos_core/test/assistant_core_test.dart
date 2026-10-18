import 'package:humanos_core/src/assistant_core.dart';
import 'package:test/test.dart';

void main() {
  const intents = [
    IntentCandidate(
      id: 'protein',
      handler: IntentHandler.proteinMissing,
      examplesEs: 'cuánta proteína me falta|me falta proteína|proteína de hoy',
    ),
    IntentCandidate(
      id: 'eat',
      handler: IntentHandler.whatToEatNow,
      examplesEs: 'qué como ahora|qué puedo comer|mejor opción ahora',
    ),
    IntentCandidate(
      id: 'pr',
      handler: IntentHandler.lastPr,
      examplesEs: 'mi último récord|último PR|cuál fue mi récord',
    ),
  ];

  test('FTS query uses content words as prefixes', () {
    expect(
      buildIntentFtsQuery('¿Cuánta proteína me falta hoy?'),
      'proteina* OR falta*',
    );
    expect(buildIntentFtsQuery('¿y?'), isNull);
  });

  test('ranking picks the right handler with confidence', () {
    final r = rankIntents('cuanta proteina me falta', intents);
    expect(r.first.candidate.handler, IntentHandler.proteinMissing);
    expect(r.first.confident, isTrue);
    final eat = rankIntents('¿Qué puedo comer ahora?', intents);
    expect(eat.first.candidate.handler, IntentHandler.whatToEatNow);
  });

  test('unrelated text is not confident (goes to Tier 1)', () {
    final r = rankIntents('háblame de la luna', intents);
    expect(r.first.confident, isFalse);
  });

  test('Tier 2 gate: 6 GB total and 1,5 GB free', () {
    expect(tier2Gate(totalRamGb: 8, availableRamGb: 2.1).allowed, isTrue);
    final low = tier2Gate(totalRamGb: 8, availableRamGb: 1.2);
    expect(low.allowed, isFalse);
    expect(low.reasonEs, contains('1,2 GB'));
    expect(tier2Gate(totalRamGb: 4, availableRamGb: 3).allowed, isFalse);
    expect(tier2Gate(totalRamGb: null, availableRamGb: 3).allowed, isFalse);
  });

  test('context is trimmed to the budget, most important lines first', () {
    final ctx = AssistantContext([
      'META: 2900 kcal y 117 g de proteína',
      'HOY: 1800 kcal y 70 g de proteína',
      for (var i = 0; i < 200; i++) 'DETALLE $i: dato secundario largo',
    ]);
    final text = ctx.render(budgetTokens: 60);
    expect(text, startsWith('CONTEXTO:'));
    expect(text, contains('META'));
    expect(estimateTokens(text), lessThanOrEqualTo(60));
    final prompt = tier2Prompt(context: ctx, question: '¿Cuánto me falta?');
    expect(estimateTokens(prompt), lessThanOrEqualTo(tier2ContextTokens));
    expect(prompt, contains('<|im_start|>assistant'));
  });

  test('the system prompt forbids diagnoses and invented numbers', () {
    expect(tier2SystemPromptEs, contains('no inventes números'));
    expect(tier2SystemPromptEs, contains('No diagnostiques'));
    expect(tier2SystemPromptEs, contains('911'));
  });

  test('handler codes round-trip', () {
    for (final h in IntentHandler.values) {
      expect(IntentHandler.parse(h.code), h);
    }
    expect(IntentHandler.parse('x'), isNull);
  });
}
