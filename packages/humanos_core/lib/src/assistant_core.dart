/// Pure parts of the tiered on-device assistant.
///
/// * Tier 0: [buildIntentFtsQuery] turns the user's text into an FTS5 query
///   for `intents_fts`; [rankIntents] re-ranks the candidates by token
///   overlap and decides whether the match is confident.
/// * Tier 2: [AssistantContext] renders the SQL-built summary within a
///   token budget, and [tier2SystemPromptEs] forbids diagnoses and invented
///   numbers. The model only rewrites what the context already says.
/// * Device gate for Tier 2: total RAM ≥ 6 GB and available ≥ 1.5 GB.
library;

import 'text_es.dart';

/// Handlers implemented by the app (Tier 0 answers from templates).
enum IntentHandler {
  whatToEatNow('what_to_eat_now'),
  proteinMissing('protein_missing'),
  lastPr('last_pr'),
  nextSession('next_session'),
  metricMeaning('metric_meaning'),
  toxSummary('tox_summary'),
  readinessExplain('readiness_explain'),
  logByText('log_by_text'),
  sleepSummary('sleep_summary'),
  streakStatus('streak_status');

  const IntentHandler(this.code);

  /// Stored in `intents.handler`.
  final String code;

  static IntentHandler? parse(String? code) {
    for (final h in IntentHandler.values) {
      if (h.code == code) return h;
    }
    return null;
  }
}

/// FTS5 query: content tokens as prefix terms joined with OR. Null when the
/// text has no content words.
String? buildIntentFtsQuery(String text) {
  final tokens = contentTokensEs(
    text,
  ).where((t) => t.length >= 2 && RegExp(r'^[a-z0-9]+$').hasMatch(t)).toSet();
  if (tokens.isEmpty) return null;
  return tokens.map((t) => '$t*').join(' OR ');
}

/// One candidate row from `intents_fts` (examples separated by "|").
class IntentCandidate {
  const IntentCandidate({
    required this.id,
    required this.handler,
    required this.examplesEs,
  });

  final String id;
  final IntentHandler handler;
  final String examplesEs;
}

class IntentMatch {
  const IntentMatch({
    required this.candidate,
    required this.score,
    required this.confident,
  });

  final IntentCandidate candidate;

  /// Best Jaccard-like overlap with one example, 0..1.
  final double score;

  /// Below the threshold Tier 1 (embeddings) is asked, if installed.
  final bool confident;
}

/// Minimum overlap for a confident Tier 0 match. Part of the matcher's
/// definition, not a health assumption.
const double intentConfidentScore = 0.34;

double _overlap(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var shared = 0;
  for (final t in a) {
    if (b.any(
      (u) =>
          u == t ||
          (t.length >= 4 && u.startsWith(t)) ||
          (u.length >= 4 && t.startsWith(u)),
    )) {
      shared++;
    }
  }
  return shared / (a.length + b.length - shared);
}

/// Ranks [candidates] against [text]; best first.
List<IntentMatch> rankIntents(String text, List<IntentCandidate> candidates) {
  final query = contentTokensEs(text).toSet();
  final ranked = <IntentMatch>[];
  for (final c in candidates) {
    var best = 0.0;
    for (final example in c.examplesEs.split('|')) {
      final score = _overlap(query, contentTokensEs(example).toSet());
      if (score > best) best = score;
    }
    ranked.add(
      IntentMatch(
        candidate: c,
        score: best,
        confident: best >= intentConfidentScore,
      ),
    );
  }
  ranked.sort((a, b) => b.score.compareTo(a.score));
  return ranked;
}

/// Tier 2 device gate (§10).
const double tier2MinTotalRamGb = 6;
const double tier2MinAvailableRamGb = 1.5;

/// Context window used for Tier 2 (tokens).
const int tier2ContextTokens = 1024;

class Tier2Gate {
  const Tier2Gate({required this.allowed, required this.reasonEs});
  final bool allowed;
  final String reasonEs;
}

Tier2Gate tier2Gate({
  required double? totalRamGb,
  required double? availableRamGb,
}) {
  if (totalRamGb == null || availableRamGb == null) {
    return const Tier2Gate(
      allowed: false,
      reasonEs: 'No se pudo medir la memoria: se usa el asistente básico.',
    );
  }
  if (totalRamGb < tier2MinTotalRamGb) {
    return Tier2Gate(
      allowed: false,
      reasonEs:
          'Tu teléfono tiene ${totalRamGb.toStringAsFixed(1).replaceAll('.', ',')} GB '
          'de RAM; el modelo grande necesita 6 GB.',
    );
  }
  if (availableRamGb < tier2MinAvailableRamGb) {
    return Tier2Gate(
      allowed: false,
      reasonEs:
          'Ahora hay ${availableRamGb.toStringAsFixed(1).replaceAll('.', ',')} GB '
          'libres; hacen falta 1,5 GB. Cierra apps y vuelve a intentar.',
    );
  }
  return const Tier2Gate(allowed: true, reasonEs: 'Memoria suficiente.');
}

/// System prompt for Tier 2. Spanish, short, strict.
const String tier2SystemPromptEs =
    'Eres el asistente de HumanOS. Respondes en español de Ecuador, en '
    'pocas frases y de tú. Usa SOLO los datos del bloque CONTEXTO: no '
    'inventes números, alimentos, cargas ni fechas. Si el dato no está en '
    'el contexto, di "no tengo ese dato". No diagnostiques enfermedades ni '
    'recomiendes medicamentos. Si mencionan dolor en el pecho, desmayo, '
    'sangre o falta de aire, responde solo: "Busca atención médica ahora; '
    'si es una emergencia llama al 911."';

/// Rough token estimate (≈ 4 characters per token for Spanish text).
int estimateTokens(String text) => (text.length / 4).ceil();

/// SQL-built facts for Tier 2. Each line is "LABEL: value" and lines are
/// dropped from the end (lowest priority) to fit the budget.
class AssistantContext {
  const AssistantContext(this.lines);

  /// Ordered by priority, most important first.
  final List<String> lines;

  /// The context block, within [budgetTokens] tokens.
  String render({int budgetTokens = 600}) {
    final out = <String>[];
    var used = estimateTokens('CONTEXTO:\n');
    for (final line in lines) {
      final cost = estimateTokens('$line\n');
      if (used + cost > budgetTokens) break;
      out.add(line);
      used += cost;
    }
    return 'CONTEXTO:\n${out.join('\n')}';
  }
}

/// Full prompt in the Qwen chat template, sized for [tier2ContextTokens].
String tier2Prompt({
  required AssistantContext context,
  required String question,
  int answerTokens = 256,
}) {
  final budget =
      tier2ContextTokens -
      answerTokens -
      estimateTokens(tier2SystemPromptEs) -
      estimateTokens(question) -
      32;
  final ctx = context.render(budgetTokens: budget < 64 ? 64 : budget);
  return '<|im_start|>system\n$tier2SystemPromptEs\n<|im_end|>\n'
      '<|im_start|>user\n$ctx\n\nPREGUNTA: $question\n<|im_end|>\n'
      '<|im_start|>assistant\n';
}
