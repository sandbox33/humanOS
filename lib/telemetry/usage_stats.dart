import 'package:flutter/services.dart';

/// Screen time from Android's UsageStatsManager through the
/// `UsageStatsChannel.kt` platform channel. The permission is granted by the
/// user in system settings (PACKAGE_USAGE_STATS).
abstract class ScreenTimeSource {
  Future<bool> hasPermission();
  Future<void> openSettings();

  /// Foreground minutes from local midnight until now, or null without
  /// permission.
  Future<int?> minutesToday();
}

class UsageStatsScreenTime implements ScreenTimeSource {
  static const _channel = MethodChannel('com.altair.humanos/usage_stats');

  @override
  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;

  @override
  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');

  @override
  Future<int?> minutesToday() async {
    if (!await hasPermission()) return null;
    final ms = await _channel.invokeMethod<int>('foregroundMsToday');
    return ms == null ? null : (ms / 60000).round();
  }
}
