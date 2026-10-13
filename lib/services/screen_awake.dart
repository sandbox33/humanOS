import 'package:flutter/services.dart';

/// Keeps the screen on during a Heavy Duty session.
abstract class ScreenAwake {
  Future<void> keepOn(bool on);
}

/// `FLAG_KEEP_SCREEN_ON` on the activity window through the app's own
/// channel (`MainActivity.kt`), so no extra plugin is needed.
class WindowScreenAwake implements ScreenAwake {
  static const _channel = MethodChannel('com.altair.humanos/screen');

  @override
  Future<void> keepOn(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', {'on': on});
    } on MissingPluginException {
      // Not on Android (widget tests): nothing to keep awake.
    }
  }
}

class NoopScreenAwake implements ScreenAwake {
  bool on = false;
  @override
  Future<void> keepOn(bool value) async => on = value;
}
