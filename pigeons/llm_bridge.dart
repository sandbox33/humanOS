// Source of `lib/services/llm_bridge.pigeon.dart` and `LlmBridge.g.kt`.
// Regenerate with pigeon 29.1.0 in a separate Dart package (the app does
// not depend on pigeon): dart run pigeon --input pigeons/llm_bridge.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/services/llm_bridge.pigeon.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/altair/humanos/LlmBridge.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.altair.humanos'),
    dartPackageName: 'humanos',
  ),
)
/// Result of loading the model file.
class LlmLoadResult {
  LlmLoadResult({required this.loaded, required this.loadMs, this.errorEs});

  bool loaded;
  int loadMs;
  String? errorEs;
}

/// One completion: the text, or why there is none.
class LlmReply {
  LlmReply({required this.elapsedMs, this.text, this.errorEs});

  int elapsedMs;
  String? text;
  String? errorEs;
}

/// The on-device model (LiteRT-LM), loaded on demand off the UI thread and
/// unloaded after a period without requests.
@HostApi()
abstract class LlmBridge {
  @async
  LlmLoadResult load(String modelPath, int maxTokens, int idleSeconds);

  @async
  LlmReply generate(String prompt, int timeoutMs);

  void unload();

  bool isLoaded();

  /// Total RAM of the phone in bytes.
  int totalMemoryBytes();
}
