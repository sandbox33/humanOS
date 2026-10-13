/// Telemetry types read from Health Connect, with the confidence the plan
/// assigns to each when it comes from a wrist band (Mi Fitness exports are
/// not officially documented).
enum TelemetryKind {
  steps('STEPS', 'Pasos', 'media'),
  heartRate('HEART_RATE', 'Frecuencia cardiaca', 'baja–media'),
  restingHeartRate('RESTING_HEART_RATE', 'FC en reposo', 'media'),
  hrv('HEART_RATE_VARIABILITY_RMSSD', 'VFC (rMSSD)', 'media'),
  sleepSession('SLEEP_SESSION', 'Sueño total', 'media'),
  sleepStages('SLEEP_STAGES', 'Fases del sueño', 'baja'),
  workout('WORKOUT', 'Entrenamientos', 'baja–media'),
  totalCalories('TOTAL_CALORIES_BURNED', 'Calorías gastadas', 'baja'),
  bloodOxygen('BLOOD_OXYGEN', 'SpO2', 'baja'),
  weight('WEIGHT', 'Peso', 'media');

  const TelemetryKind(this.code, this.labelEs, this.confidenceEs);

  /// Value stored in `telemetry_samples.type` (stages use their own codes).
  final String code;
  final String labelEs;
  final String confidenceEs;

  static const sleepStageCodes = {
    'SLEEP_ASLEEP',
    'SLEEP_DEEP',
    'SLEEP_LIGHT',
    'SLEEP_REM',
    'SLEEP_AWAKE',
  };

  /// Kind of a stored sample type.
  static TelemetryKind? ofCode(String code) {
    if (sleepStageCodes.contains(code)) return TelemetryKind.sleepStages;
    for (final kind in TelemetryKind.values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}

/// One reading from Health Connect or another sensor.
class TelemetrySample {
  const TelemetrySample({
    required this.type,
    required this.start,
    required this.value,
    required this.source,
    this.end,
  });

  /// Stored type code (a [TelemetryKind.code] or a sleep stage code).
  final String type;
  final DateTime start;
  final DateTime? end;
  final double? value;
  final String source;
}
