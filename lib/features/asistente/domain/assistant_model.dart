import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../services/llm_bridge.pigeon.dart';
import '../data/model_manager.dart';
import 'local_assistant.dart';

/// The user's Hugging Face token (needed for the license-gated model),
/// kept in the Android Keystore like the database key.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String? token);
}

class SecureTokenStore implements TokenStore {
  static const _key = 'hf_token_v1';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? token) =>
      token == null || token.trim().isEmpty ? _storage.delete(key: _key) : _storage.write(key: _key, value: token.trim());
}

/// The phone's model runtime; null where there is none (tests, desktop).
final llmBridgeProvider = Provider<LlmBridge?>((ref) => null);
final modelManagerProvider = Provider<ModelManager>((ref) => ModelManager());
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

abstract final class AssistantKey {
  static const model = 'assistant_model';
  static const enabled = 'assistant_model_enabled';
  static const evaluation = 'assistant_evaluation';
}

/// The last evaluation run on the phone.
class EvaluationRecord {
  const EvaluationRecord({
    required this.modelId,
    required this.withModel,
    required this.total,
    required this.correct,
    required this.medianMs,
    required this.p95Ms,
    required this.at,
  });

  factory EvaluationRecord.fromJson(Map<String, dynamic> m) => EvaluationRecord(
        modelId: m['model'] as String?,
        withModel: m['withModel'] as bool? ?? false,
        total: m['total'] as int? ?? 0,
        correct: m['correct'] as int? ?? 0,
        medianMs: m['medianMs'] as int? ?? 0,
        p95Ms: m['p95Ms'] as int? ?? 0,
        at: m['at'] as String? ?? '',
      );

  final String? modelId;
  final bool withModel;
  final int total;
  final int correct;
  final int medianMs;
  final int p95Ms;
  final String at;

  double get accuracy => total == 0 ? 0 : correct / total;

  Map<String, Object?> toJson() => {
        'model': modelId,
        'withModel': withModel,
        'total': total,
        'correct': correct,
        'medianMs': medianMs,
        'p95Ms': p95Ms,
        'at': at,
      };
}

final selectedModelProvider = Provider<ModelSpec>((ref) {
  final map = ref.watch(settingsMapProvider).value ?? const {};
  return specById(map[AssistantKey.model]) ?? modelSpecs.first;
});

final evaluationProvider = Provider<EvaluationRecord?>((ref) {
  final raw = (ref.watch(settingsMapProvider).value ?? const {})[AssistantKey.evaluation];
  if (raw == null) return null;
  try {
    return EvaluationRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } on Object {
    return null;
  }
});

final modelInstalledProvider = FutureProvider<bool>((ref) async {
  final spec = ref.watch(selectedModelProvider);
  return ref.watch(modelManagerProvider).isInstalled(spec);
});

/// The model is used when installed and either the user turned it on, or
/// they did not decide and the phone's evaluation of this model reached the
/// minimum accuracy (the brief: on by default only above the threshold).
final modelEnabledProvider = Provider<bool>((ref) {
  if (ref.watch(llmBridgeProvider) == null) return false;
  if (ref.watch(modelInstalledProvider).value != true) return false;
  final choice = (ref.watch(settingsMapProvider).value ?? const {})[AssistantKey.enabled];
  if (choice != null) return choice == '1';
  final eval = ref.watch(evaluationProvider);
  final threshold = ref.watch(currentAssumptionsProvider)[A.assistantMinAccuracy];
  return eval != null &&
      eval.withModel &&
      eval.modelId == ref.watch(selectedModelProvider).id &&
      eval.accuracy >= threshold;
});

/// One completion of the parser prompt on the phone, or null (no model,
/// load error or timeout).
Future<String?> Function(String) modelCompleter({
  required LlmBridge? bridge,
  required ModelManager manager,
  required ModelSpec spec,
  required Assumptions assumptions,
}) =>
    (prompt) async {
      if (bridge == null) return null;
      try {
        final file = await manager.fileFor(spec);
        final load = await bridge.load(file.path, assumptions.integer(A.llmMaxTokens), assumptions.integer(A.llmIdleS));
        if (!load.loaded) return null;
        final reply = await bridge.generate(prompt, assumptions.integer(A.llmTimeoutS) * 1000);
        return reply.text;
      } on Object {
        // A model that fails leaves the form to the user.
        return null;
      }
    };

/// Rules first; the model only when it is on and the rules find nothing.
final assistantProvider = Provider<LocalAssistant>((ref) => ChainedAssistant(
      rules: const RulesAssistant(),
      model: ref.watch(modelEnabledProvider)
          ? ModelAssistant(modelCompleter(
              bridge: ref.watch(llmBridgeProvider),
              manager: ref.watch(modelManagerProvider),
              spec: ref.watch(selectedModelProvider),
              assumptions: ref.watch(currentAssumptionsProvider),
            ))
          : null,
    ));

/// The evaluation set shipped with the app (invented phrases).
Future<List<EvalCase>> loadEvalSet() async =>
    parseEvalSet(await rootBundle.loadString('assets/eval/asistente_es.json'));

/// Runs [assistant] over [cases] and summarises accuracy and latency.
Future<EvalReport> evaluateAssistant(LocalAssistant assistant, List<EvalCase> cases) async {
  final outcomes = <EvalOutcome>[];
  for (final c in cases) {
    final answer = await assistant.interpret(c.phrase);
    outcomes.add(EvalOutcome(evalCase: c, got: answer.intent, elapsed: answer.elapsed));
  }
  return summarize(outcomes);
}
