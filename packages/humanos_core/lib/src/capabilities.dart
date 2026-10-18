/// Device capabilities detected at runtime (§9). Features switch on or off
/// from the `capabilities` table, never from the band model name.
///
/// Mi Fitness → Health Connect shares steps, distance, calories, sleep with
/// stages, exercise sessions (heart rate only during exercise) and weight;
/// it does not share HRV, SpO₂, breathing rate, skin temperature or heart
/// rate outside exercise. Other apps and bands may share more, so nothing is
/// assumed: the probe reads the last 7 days of each type.
library;

import 'confidence.dart';
import 'day.dart';

/// Health Connect types probed, plus one derived type.
enum HcType {
  steps('STEPS', 'Pasos'),
  distance('DISTANCE', 'Distancia'),
  totalCalories('TOTAL_CALORIES_BURNED', 'Calorías totales'),
  sleepSession('SLEEP_SESSION', 'Sueño'),
  sleepStages('SLEEP_STAGES', 'Fases del sueño'),
  workout('WORKOUT', 'Ejercicios'),
  heartRate('HEART_RATE', 'Pulso'),
  restingHeartRate('RESTING_HEART_RATE', 'FC en reposo'),
  hrv('HEART_RATE_VARIABILITY_RMSSD', 'VFC (rMSSD)'),
  bloodOxygen('BLOOD_OXYGEN', 'Oxígeno en sangre'),
  weight('WEIGHT', 'Peso'),

  /// Derived: heart-rate samples outside exercise sessions.
  heartRateOutsideExercise(
    'HEART_RATE_OUTSIDE_EXERCISE',
    'Pulso fuera del ejercicio',
  );

  const HcType(this.code, this.labelEs);

  /// Stored in `capabilities.type`.
  final String code;
  final String labelEs;

  static HcType? parse(String? code) {
    for (final t in HcType.values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// One `capabilities` row.
class CapabilityRow {
  const CapabilityRow({
    required this.type,
    required this.available,
    required this.checkedAt,
    this.lastSeen,
    this.sourcePkg,
  });

  final HcType type;
  final bool available;
  final DateTime checkedAt;
  final DateTime? lastSeen;
  final String? sourcePkg;
}

/// Days a type is looked back by the probe.
const int capabilityProbeDays = 7;

/// Heart rate counts as shared outside exercise when samples outside any
/// workout appear on at least this many distinct days of the probe window.
const int hrOutsideExerciseMinDays = 3;

/// Derives [HcType.heartRateOutsideExercise] from heart-rate sample times
/// and workout intervals (start, end).
bool hrOutsideExerciseAvailable(
  List<DateTime> heartRateTimes,
  List<(DateTime, DateTime)> workouts,
) {
  final days = <DateTime>{};
  for (final t in heartRateTimes) {
    final inWorkout = workouts.any(
      (w) => !t.isBefore(w.$1) && !t.isAfter(w.$2),
    );
    if (!inWorkout) days.add(dateOnly(t));
  }
  return days.length >= hrOutsideExerciseMinDays;
}

/// Confidence of each data type when it comes from a wrist band.
class ConfidenceRange {
  const ConfidenceRange(this.low, this.high);
  final Confidence low;
  final Confidence high;

  String get labelEs => low == high ? low.code : '${low.code}–${high.code}';
}

/// Chips shown next to telemetry values (§9).
ConfidenceRange dataConfidence(HcType type) => switch (type) {
  HcType.steps ||
  HcType.distance ||
  HcType.sleepSession ||
  HcType.weight => const ConfidenceRange(Confidence.media, Confidence.media),
  HcType.sleepStages ||
  HcType.totalCalories ||
  HcType.bloodOxygen => const ConfidenceRange(Confidence.baja, Confidence.baja),
  HcType.workout ||
  HcType.heartRate ||
  HcType.heartRateOutsideExercise ||
  HcType.restingHeartRate ||
  HcType.hrv => const ConfidenceRange(Confidence.baja, Confidence.media),
};

/// Features that depend on device data.
enum DeviceFeature {
  readinessHrv('Preparación con VFC', [HcType.hrv]),
  readinessRestingHr('Preparación con FC en reposo', [HcType.restingHeartRate]),
  sleep('Sueño y deuda de sueño', [HcType.sleepSession]),
  sleepStages('Fases del sueño', [HcType.sleepStages]),
  workoutHr('Pulso en tus sesiones', [HcType.workout, HcType.heartRate]),
  stressContext('Pregunta de contexto por pulso alto', [
    HcType.heartRateOutsideExercise,
  ]),
  steps('Pasos del día', [HcType.steps]),
  weightSync('Peso desde la báscula o la app', [HcType.weight]);

  const DeviceFeature(this.labelEs, this.requires);
  final String labelEs;
  final List<HcType> requires;
}

class FeatureStatus {
  const FeatureStatus({
    required this.feature,
    required this.available,
    required this.detailEs,
  });

  final DeviceFeature feature;

  /// Null when the probe has not run yet.
  final bool? available;
  final String detailEs;
}

/// One row per feature for the Diagnóstico screen.
List<FeatureStatus> featureAvailability(Map<HcType, CapabilityRow> rows) => [
  for (final f in DeviceFeature.values) _status(f, rows),
];

FeatureStatus _status(DeviceFeature f, Map<HcType, CapabilityRow> rows) {
  final missing = <HcType>[];
  var unknown = false;
  for (final t in f.requires) {
    final row = rows[t];
    if (row == null) {
      unknown = true;
    } else if (!row.available) {
      missing.add(t);
    }
  }
  if (missing.isNotEmpty) {
    return FeatureStatus(
      feature: f,
      available: false,
      detailEs:
          '${f.labelEs}: no disponible con tu dispositivo '
          '(${missing.map((t) => t.labelEs).join(', ')} sin datos en '
          '$capabilityProbeDays días).',
    );
  }
  if (unknown) {
    return FeatureStatus(
      feature: f,
      available: null,
      detailEs: '${f.labelEs}: aún sin comprobar.',
    );
  }
  return FeatureStatus(
    feature: f,
    available: true,
    detailEs: '${f.labelEs}: disponible.',
  );
}

/// Steps to turn on Mi Fitness → Health Connect sync (Diagnóstico).
const List<String> miFitnessSyncStepsEs = [
  'Instala Health Connect desde Google Play si tu Android no lo trae.',
  'Abre Mi Fitness → Perfil → Agregar cuentas (o Apps de terceros) → '
      'Health Connect y activa la sincronización.',
  'En Health Connect → Permisos de apps → Mi Fitness, permite escribir '
      'pasos, sueño, ejercicio, calorías y peso.',
  'En Health Connect → Permisos de apps → HumanOS, permite leer esos '
      'datos y la lectura en segundo plano.',
  'Vuelve a HumanOS → DIAGNÓSTICO → Comprobar ahora.',
];

/// "?" note on the advanced alternative to Mi Fitness.
const String gadgetbridgeNoteEs =
    'Opción avanzada y experimental: Gadgetbridge (app libre) puede '
    'reemplazar a Mi Fitness con algunas bandas Xiaomi y compartir más '
    'datos. Requiere obtener la clave de la banda y no es necesaria para '
    'usar HumanOS.';

/// BLE heart-rate hint (§9): offered only if a device advertising 0x180D
/// is found.
const String bleHintEs =
    'Pulso en vivo por Bluetooth: funciona con dispositivos que emiten el '
    'servicio estándar de pulso (0x180D), como la Smart Band 10 / 10 Pro '
    'o una banda de pecho. La Band 9 no lo emite.';
