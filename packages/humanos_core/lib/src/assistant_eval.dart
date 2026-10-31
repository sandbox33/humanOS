/// The on-device model's job description, and how the assistant is
/// measured on the phone (accuracy and latency) before it may be turned on
/// by default.
library;

import 'dart:convert';

import 'log_parser.dart';

/// Prompt for the on-device model: it only converts a phrase into one JSON
/// object of the schema, or `{"accion": null}`. No conversation, no advice.
/// The examples are invented and differ from the evaluation set.
String buildParserPrompt(String phrase) {
  final clean = phrase.replaceAll(RegExp(r'\s+'), ' ').trim();
  return '''
Convierte la frase en UN objeto JSON y nada más. No conversas ni das consejos.
Acciones y campos:
- work_entry: label (texto), minutes (entero), start y end ("HH:MM"), rate_cents (centavos por hora), total_cents (centavos).
- weight: kg (número).
- food_log: food (texto), grams (número), quantity (número).
- state: value (1 a 5).
- thermos: moment ("antes" o "pausa").
Si la frase no es un registro de esas acciones, responde {"accion": null}.
Ejemplos:
Frase: 5 horas de jardinería a 3,80
JSON: {"accion": "work_entry", "minutes": 300, "rate_cents": 380, "label": "jardinería"}
Frase: entré a las 6 y salí a las 2
JSON: {"accion": "work_entry", "start": "06:00", "end": "14:00"}
Frase: me dieron 12 dólares por cargar cajas
JSON: {"accion": "work_entry", "total_cents": 1200}
Frase: la balanza dice 74 kilos
JSON: {"accion": "weight", "kg": 74.0}
Frase: hoy ando con energía 3
JSON: {"accion": "state", "value": 3}
Frase: eché agua al termo en el receso
JSON: {"accion": "thermos", "moment": "pausa"}
Frase: me zampé 300 g de papas
JSON: {"accion": "food_log", "grams": 300.0, "food": "papas"}
Frase: cuéntame un chiste
JSON: {"accion": null}
Frase: $clean
JSON:''';
}

/// The model's answer as a record, or null (no JSON, `accion: null` or a
/// record that breaks the schema).
LogIntent? intentFromModelOutput(String output) {
  final json = extractJsonObject(output);
  if (json is Map && json['accion'] == null) return null;
  return validateLogJson(json).intent;
}

class EvalCase {
  const EvalCase(this.phrase, this.expected);

  final String phrase;

  /// Null when the phrase must not become a record.
  final LogIntent? expected;
}

/// Reads the evaluation set (`assets/eval/asistente_es.json`). Every
/// expected record must itself pass the schema.
List<EvalCase> parseEvalSet(String text) {
  final data = jsonDecode(text) as Map<String, dynamic>;
  return [
    for (final c in data['casos'] as List<dynamic>)
      () {
        final map = c as Map<String, dynamic>;
        final expected = map['esperado'];
        final LogIntent? intent;
        if (expected == null) {
          intent = null;
        } else {
          final v = validateLogJson(expected);
          if (!v.ok) {
            throw FormatException(
              'Caso inválido: ${map['frase']}: ${v.problemsEs.join(' ')}',
            );
          }
          intent = v.intent;
        }
        return EvalCase(map['frase'] as String, intent);
      }(),
  ];
}

class EvalOutcome {
  const EvalOutcome({
    required this.evalCase,
    required this.got,
    required this.elapsed,
  });

  final EvalCase evalCase;
  final LogIntent? got;
  final Duration elapsed;

  bool get correct => got == evalCase.expected;
}

class EvalReport {
  const EvalReport({
    required this.total,
    required this.correct,
    required this.medianMs,
    required this.p95Ms,
    required this.failures,
  });

  final int total;
  final int correct;
  final int medianMs;
  final int p95Ms;
  final List<EvalOutcome> failures;

  double get accuracy => total == 0 ? 0 : correct / total;

  /// The assistant may be on by default only at or above [threshold].
  bool passes(double threshold) => total > 0 && accuracy >= threshold;
}

int _percentile(List<int> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final index = ((sorted.length - 1) * p).round();
  return sorted[index];
}

EvalReport summarize(List<EvalOutcome> outcomes) {
  final ms = [for (final o in outcomes) o.elapsed.inMilliseconds]..sort();
  return EvalReport(
    total: outcomes.length,
    correct: outcomes.where((o) => o.correct).length,
    medianMs: _percentile(ms, 0.5),
    p95Ms: _percentile(ms, 0.95),
    failures: [
      for (final o in outcomes)
        if (!o.correct) o,
    ],
  );
}
