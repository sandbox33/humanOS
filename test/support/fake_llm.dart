import 'dart:io';

import 'package:humanos/features/asistente/data/model_manager.dart';
import 'package:humanos/services/llm_bridge.pigeon.dart';

/// A model that answers from a table of prompts' last phrase; test data
/// only.
class FakeLlm extends LlmBridge {
  FakeLlm(this.answers);

  /// Phrase → raw model output.
  final Map<String, String> answers;
  final prompts = <String>[];
  bool loaded = false;

  @override
  Future<LlmLoadResult> load(String modelPath, int maxTokens, int idleSeconds) async {
    loaded = true;
    return LlmLoadResult(loaded: true, loadMs: 5);
  }

  @override
  Future<LlmReply> generate(String prompt, int timeoutMs) async {
    prompts.add(prompt);
    final phrase = RegExp(r'Frase: (.*)\nJSON:$').firstMatch(prompt)?.group(1) ?? '';
    return LlmReply(elapsedMs: 12, text: answers[phrase] ?? 'no sé');
  }

  @override
  Future<void> unload() async => loaded = false;

  @override
  Future<bool> isLoaded() async => loaded;

  @override
  Future<int> totalMemoryBytes() async => 4 * 1024 * 1024 * 1024;
}

/// Model files without disk access; test data only.
class FakeModelManager extends ModelManager {
  FakeModelManager({this.installed = false});

  bool installed;

  @override
  Future<File> fileFor(ModelSpec spec) async => File('modelos/${spec.fileName}');

  @override
  Future<bool> isInstalled(ModelSpec spec) async => installed;
}
