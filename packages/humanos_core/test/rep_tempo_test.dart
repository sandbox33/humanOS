import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  final p = TempoParams.fromAssumptions(Assumptions.defaults());
  final spec = TempoSpec.parse('4-1-X-2');

  test('parses 4-1-X-2', () {
    expect(spec.eccentricS, 4);
    expect(spec.bottomPauseS, 1);
    expect(spec.concentricS, isNull);
    expect(spec.topPauseS, 2);
    expect(spec.cycleSeconds(1.0), 8);
    expect(() => TempoSpec.parse('4-1-X'), throwsFormatException);
  });

  test('reps following the tempo are valid and TUT is the elapsed time', () {
    // First rep has no top pause: 4 + 1 + 1 = 6 s, then 8 s cycles.
    final taps = [6000, 14000, 22000, 30000];
    final a = analyzeReps(taps, spec, p);
    expect(a.reps, 4);
    expect(a.validReps, 4);
    expect(a.tutS, 30);
    expect(a.eccentricEstimatesS.first, closeTo(4, 1e-9));
  });

  test('rushed reps (eccentric < 3 s) are not valid', () {
    final taps = [6000, 10000, 14000];
    final a = analyzeReps(taps, spec, p);
    expect(a.reps, 3);
    expect(a.validReps, 1);
    expect(a.valid, [true, false, false]);
  });

  test('exactly 3 s of eccentric counts', () {
    final a = analyzeReps([5000], spec, p);
    expect(a.eccentricEstimatesS.single, closeTo(3, 1e-9));
    expect(a.validReps, 1);
  });

  test('double taps are debounced', () {
    final a = analyzeReps([6000, 6100, 14000], spec, p);
    expect(a.reps, 2);
  });

  test('metronome position walks the phases', () {
    expect(metronomeAt(spec, 0, 1).phase.kind, TempoPhaseKind.eccentric);
    expect(metronomeAt(spec, 4500, 1).phase.kind, TempoPhaseKind.bottomPause);
    expect(metronomeAt(spec, 5200, 1).phase.kind, TempoPhaseKind.concentric);
    final top = metronomeAt(spec, 7000, 1);
    expect(top.phase.kind, TempoPhaseKind.topPause);
    expect(top.phaseRemainingS, closeTo(1, 1e-9));
    expect(metronomeAt(spec, 8100, 1).repIndex, 1);
  });

  test('tempo without pauses skips them', () {
    final s = TempoSpec.parse('3-0-1-0');
    expect(s.phases(1).length, 2);
  });
}
