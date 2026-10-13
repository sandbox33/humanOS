import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on during a Heavy Duty session.
abstract class ScreenAwake {
  Future<void> keepOn(bool on);
}

class WakelockScreenAwake implements ScreenAwake {
  @override
  Future<void> keepOn(bool on) => WakelockPlus.toggle(enable: on);
}

class NoopScreenAwake implements ScreenAwake {
  bool on = false;
  @override
  Future<void> keepOn(bool value) async => on = value;
}
