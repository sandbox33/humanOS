import 'package:flutter/services.dart';
import 'package:humanos_core/humanos_core.dart';

/// Screen time from Android's UsageStatsManager through the
/// `UsageStatsChannel.kt` platform channel. The permission is granted by the
/// user in system settings (PACKAGE_USAGE_STATS).
abstract class ScreenTimeSource {
  Future<bool> hasPermission();
  Future<void> openSettings();

  /// Foreground minutes from local midnight until now, or null without
  /// permission.
  Future<int?> minutesToday();

  /// Resume/pause events of every app (HumanOS excluded) between [from]
  /// and [to]; null without permission. The phone keeps only some days.
  Future<List<UsageEvent>?> events(DateTime from, DateTime to);

  /// The category each app declares to Android (first suggestion only).
  Future<Map<String, int>> appCategories();
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

  @override
  Future<List<UsageEvent>?> events(DateTime from, DateTime to) async {
    final raw = await _channel.invokeMethod<List<Object?>>(
      'events',
      {'fromMs': from.millisecondsSinceEpoch, 'toMs': to.millisecondsSinceEpoch},
    );
    if (raw == null) return null;
    return [
      for (final item in raw)
        if (item is Map)
          UsageEvent(
            package: item['package'] as String,
            activity: item['activity'] as String? ?? '',
            type: item['type'] == 'resumed' ? UsageEventType.resumed : UsageEventType.paused,
            at: DateTime.fromMillisecondsSinceEpoch((item['at'] as num).toInt()),
          ),
    ];
  }

  @override
  Future<Map<String, int>> appCategories() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('appCategories') ?? const {};
    return {
      for (final e in raw.entries)
        if (e.key is String && e.value is int) e.key as String: e.value as int,
    };
  }
}
