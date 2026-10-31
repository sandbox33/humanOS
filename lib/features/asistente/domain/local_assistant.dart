import 'package:humanos_core/humanos_core.dart';

/// What the assistant understood from one phrase. Nothing is written: the
/// app opens the matching form with [intent] (or [draft]) and the user
/// confirms.
class AssistantAnswer {
  const AssistantAnswer({
    required this.phrase,
    required this.source,
    required this.elapsed,
    this.intent,
    this.draft,
    this.problemsEs = const [],
  });

  final String phrase;

  /// `reglas` or `modelo`; null when nothing was understood.
  final String? source;
  final Duration elapsed;

  /// A record that passes the schema.
  final LogIntent? intent;

  /// An incomplete record: the form asks for what is missing.
  final LogIntent? draft;
  final List<String> problemsEs;

  LogIntent? get best => intent ?? draft;
}

/// Two implementations (rules and the on-device model), interchangeable
/// and testable without a phone.
abstract class LocalAssistant {
  String get nameEs;

  Future<AssistantAnswer> interpret(String phrase);
}

class RulesAssistant implements LocalAssistant {
  const RulesAssistant();

  @override
  String get nameEs => 'Reglas';

  @override
  Future<AssistantAnswer> interpret(String phrase) async {
    final watch = Stopwatch()..start();
    final found = parseByRules(phrase);
    if (found == null) return AssistantAnswer(phrase: phrase, source: null, elapsed: watch.elapsed);
    final check = validateLogJson(found.toJson());
    return AssistantAnswer(
      phrase: phrase,
      source: 'reglas',
      elapsed: watch.elapsed,
      intent: check.intent,
      draft: check.ok ? null : found,
      problemsEs: check.problemsEs,
    );
  }
}

/// Sends the parser prompt to the on-device model and validates its JSON.
/// [complete] returns the model's text, or null on error or timeout.
class ModelAssistant implements LocalAssistant {
  const ModelAssistant(this.complete);

  final Future<String?> Function(String prompt) complete;

  @override
  String get nameEs => 'Modelo en el teléfono';

  @override
  Future<AssistantAnswer> interpret(String phrase) async {
    final watch = Stopwatch()..start();
    final output = await complete(buildParserPrompt(phrase));
    final intent = output == null ? null : intentFromModelOutput(output);
    return AssistantAnswer(
      phrase: phrase,
      source: intent == null ? null : 'modelo',
      elapsed: watch.elapsed,
      intent: intent,
    );
  }
}

/// Rules first; the model only when the rules find nothing and it is on.
class ChainedAssistant implements LocalAssistant {
  const ChainedAssistant({required this.rules, this.model});

  final LocalAssistant rules;
  final LocalAssistant? model;

  @override
  String get nameEs => model == null ? rules.nameEs : '${rules.nameEs} + ${model!.nameEs}';

  @override
  Future<AssistantAnswer> interpret(String phrase) async {
    final first = await rules.interpret(phrase);
    final model = this.model;
    if (first.source != null || model == null) return first;
    final second = await model.interpret(phrase);
    return AssistantAnswer(
      phrase: phrase,
      source: second.source,
      elapsed: first.elapsed + second.elapsed,
      intent: second.intent,
      draft: second.draft,
      problemsEs: second.problemsEs,
    );
  }
}
