import 'package:health/health.dart';

import 'confidence.dart';

enum HealthAvailability { available, needsInstall, unavailable }

/// Read-only access to Health Connect.
abstract class HealthSource {
  Future<HealthAvailability> availability();

  /// Asks for read access to every type of the plan, background reading
  /// and history. Returns whether the main permissions were granted.
  Future<bool> requestPermissions();
  Future<void> installHealthConnect();
  Future<List<TelemetrySample>> read(DateTime from, DateTime to);
}

/// Health Connect through the `health` plugin.
class PluginHealthSource implements HealthSource {
  PluginHealthSource() : _health = Health();

  final Health _health;
  bool _configured = false;

  static const types = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.WORKOUT,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.WEIGHT,
  ];

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<HealthAvailability> availability() async {
    await _configure();
    final status = await _health.getHealthConnectSdkStatus();
    return switch (status) {
      HealthConnectSdkStatus.sdkAvailable => HealthAvailability.available,
      HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
        HealthAvailability.needsInstall,
      _ => HealthAvailability.unavailable,
    };
  }

  @override
  Future<bool> requestPermissions() async {
    await _configure();
    final granted = await _health.requestAuthorization(
      types,
      permissions: List.filled(types.length, HealthDataAccess.READ),
    );
    if (granted) {
      await _health.requestHealthDataHistoryAuthorization();
      await _health.requestHealthDataInBackgroundAuthorization();
    }
    return granted;
  }

  @override
  Future<void> installHealthConnect() => _health.installHealthConnect();

  @override
  Future<List<TelemetrySample>> read(DateTime from, DateTime to) async {
    await _configure();
    final points = await _health.getHealthDataFromTypes(
      types: types,
      startTime: from,
      endTime: to,
    );
    final samples = <TelemetrySample>[];
    for (final p in _health.removeDuplicates(points)) {
      final double? value;
      if (p.type == HealthDataType.WORKOUT ||
          p.type == HealthDataType.SLEEP_SESSION ||
          TelemetryKind.sleepStageCodes.contains(p.type.name)) {
        value = p.dateTo.difference(p.dateFrom).inSeconds / 60;
      } else {
        final v = p.value;
        value = v is NumericHealthValue ? v.numericValue.toDouble() : null;
      }
      samples.add(TelemetrySample(
        type: p.type.name,
        start: p.dateFrom,
        end: p.dateTo,
        value: value,
        source: p.sourceName.isEmpty ? p.sourceId : p.sourceName,
      ));
    }
    return samples;
  }
}
