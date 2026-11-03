import 'dart:io';

import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  // The same file the app ships to measure the assistant on the phone.
  final cases = parseEvalSet(
    File('../../assets/eval/asistente_es.json').readAsStringSync(),
  );

  test(
    'the evaluation set has 30–50 phrases and every expected record is valid',
    () {
      expect(cases.length, inInclusiveRange(30, 50));
      expect(
        cases.where((c) => c.expected == null),
        isNotEmpty,
        reason: 'phrases that must stay unrecorded',
      );
    },
  );

  test('the rules alone solve most of the set and never invent a record', () {
    final outcomes = [
      for (final c in cases)
        EvalOutcome(
          evalCase: c,
          got: switch (parseByRules(c.phrase)) {
            final r? => validateLogJson(r.toJson()).intent,
            null => null,
          },
          elapsed: Duration.zero,
        ),
    ];
    final report = summarize(outcomes);
    expect(report.accuracy, greaterThanOrEqualTo(0.9));
    for (final f in report.failures) {
      expect(
        f.got,
        isNull,
        reason:
            'a failing rule leaves the phrase to the model: ${f.evalCase.phrase}',
      );
    }
  });

  test(
    'the prompt holds the schema and the phrase, not the evaluation phrases',
    () {
      final prompt = buildParserPrompt('  trabajé   dos horas ');
      expect(prompt, contains('work_entry'));
      expect(prompt.trimRight(), endsWith('Frase: trabajé dos horas\nJSON:'));
      for (final c in cases) {
        expect(prompt.contains(c.phrase), isFalse, reason: c.phrase);
      }
    },
  );

  test(
    "the model's answer becomes a record only when it passes the schema",
    () {
      expect(
        intentFromModelOutput('{"accion": "weight", "kg": 70}'),
        const LogIntent(LogAction.weight, {'kg': 70.0}),
      );
      expect(intentFromModelOutput('{"accion": null}'), isNull);
      expect(intentFromModelOutput('{"accion": "weight", "kg": 7}'), isNull);
      expect(intentFromModelOutput('Claro, aquí tienes un consejo…'), isNull);
    },
  );

  test('accuracy and latency of a run', () {
    const c = EvalCase('x', null);
    final report = summarize([
      for (final ms in [10, 20, 30, 40, 1000])
        EvalOutcome(
          evalCase: c,
          got: ms == 1000
              ? const LogIntent(LogAction.state, {'value': 3})
              : null,
          elapsed: Duration(milliseconds: ms),
        ),
    ]);
    expect(report.total, 5);
    expect(report.correct, 4);
    expect(report.accuracy, 0.8);
    expect(report.medianMs, 30);
    expect(report.p95Ms, 1000);
    expect(report.passes(0.9), isFalse);
    expect(report.passes(0.8), isTrue);
    expect(summarize(const []).passes(0.5), isFalse);
  });
}
