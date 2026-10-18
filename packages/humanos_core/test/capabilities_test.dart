import 'package:humanos_core/src/capabilities.dart';
import 'package:humanos_core/src/confidence.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 10, 18, 7);
  CapabilityRow row(HcType t, bool ok) =>
      CapabilityRow(type: t, available: ok, checkedAt: now);

  test('Band 9 via Mi Fitness: HRV and stress context are off', () {
    final rows = {
      for (final t in HcType.values)
        t: row(
          t,
          !{
            HcType.hrv,
            HcType.bloodOxygen,
            HcType.restingHeartRate,
            HcType.heartRateOutsideExercise,
          }.contains(t),
        ),
    };
    final status = {for (final s in featureAvailability(rows)) s.feature: s};
    expect(status[DeviceFeature.readinessHrv]!.available, isFalse);
    expect(
      status[DeviceFeature.readinessHrv]!.detailEs,
      contains('no disponible con tu dispositivo'),
    );
    expect(status[DeviceFeature.stressContext]!.available, isFalse);
    expect(status[DeviceFeature.sleep]!.available, isTrue);
    expect(status[DeviceFeature.workoutHr]!.available, isTrue);
  });

  test('unprobed types read as "aún sin comprobar"', () {
    final status = featureAvailability(const {});
    expect(status.every((s) => s.available == null), isTrue);
    expect(status.first.detailEs, contains('sin comprobar'));
  });

  test('HR outside exercise needs samples on 3 distinct days', () {
    final workout = (DateTime(2026, 10, 15, 18), DateTime(2026, 10, 15, 19));
    final inWorkout = [
      for (var m = 0; m < 50; m++) DateTime(2026, 10, 15, 18, m),
    ];
    expect(hrOutsideExerciseAvailable(inWorkout, [workout]), isFalse);
    final spread = [
      DateTime(2026, 10, 12, 10),
      DateTime(2026, 10, 13, 10),
      DateTime(2026, 10, 14, 10),
    ];
    expect(hrOutsideExerciseAvailable(spread, [workout]), isTrue);
    expect(hrOutsideExerciseAvailable(spread.take(2).toList(), []), isFalse);
  });

  test('confidence chips follow §9', () {
    expect(dataConfidence(HcType.steps).labelEs, 'media');
    expect(dataConfidence(HcType.sleepSession).labelEs, 'media');
    expect(dataConfidence(HcType.sleepStages).labelEs, 'baja');
    expect(dataConfidence(HcType.workout).labelEs, 'baja–media');
    expect(dataConfidence(HcType.totalCalories).low, Confidence.baja);
  });

  test('codes round-trip and texts exist', () {
    for (final t in HcType.values) {
      expect(HcType.parse(t.code), t);
    }
    expect(HcType.parse('X'), isNull);
    expect(miFitnessSyncStepsEs, isNotEmpty);
    expect(bleHintEs, contains('0x180D'));
    expect(gadgetbridgeNoteEs, contains('Gadgetbridge'));
  });
}
