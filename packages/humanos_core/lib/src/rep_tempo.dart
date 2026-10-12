/// Tempo analysis from tap timestamps.
///
/// The user taps once at the end of each repetition (back at the top). With
/// the prescribed tempo (e.g. `4-1-X-2`: 4 s down, 1 s pause, explosive up,
/// 2 s at the top) the eccentric of each rep is estimated as
/// `span − bottom pause − concentric − top pause` (no top pause before the
/// first rep). A rep is valid when that estimate reaches the minimum
/// eccentric time. Time under tension is the time from set start to the
/// last tap.
library;

import 'assumptions.dart';

/// One phase of the metronome cycle.
enum TempoPhaseKind {
  eccentric('BAJA'),
  bottomPause('PAUSA'),
  concentric('SUBE'),
  topPause('ARRIBA');

  const TempoPhaseKind(this.labelEs);
  final String labelEs;
}

class TempoPhase {
  const TempoPhase(this.kind, this.seconds);
  final TempoPhaseKind kind;
  final double seconds;
}

/// Prescribed tempo. [concentricS] is null for an explosive "X".
class TempoSpec {
  const TempoSpec({
    required this.eccentricS,
    required this.bottomPauseS,
    required this.concentricS,
    required this.topPauseS,
  });

  /// Parses `4-1-X-2` style notation.
  factory TempoSpec.parse(String text) {
    final parts = text.trim().toUpperCase().split('-');
    if (parts.length != 4) {
      throw FormatException('Tempo inválido, se esperaba E-P-C-A', text);
    }
    double? number(String part, {required bool allowX}) {
      if (allowX && part == 'X') return null;
      final value = double.tryParse(part.replaceAll(',', '.'));
      if (value == null || value < 0) {
        throw FormatException('Tempo inválido', text);
      }
      return value;
    }

    return TempoSpec(
      eccentricS: number(parts[0], allowX: false)!,
      bottomPauseS: number(parts[1], allowX: false)!,
      concentricS: number(parts[2], allowX: true),
      topPauseS: number(parts[3], allowX: false)!,
    );
  }

  final double eccentricS;
  final double bottomPauseS;
  final double? concentricS;
  final double topPauseS;

  /// Metronome phases; "X" lasts [concentricXS].
  List<TempoPhase> phases(double concentricXS) => [
    TempoPhase(TempoPhaseKind.eccentric, eccentricS),
    if (bottomPauseS > 0) TempoPhase(TempoPhaseKind.bottomPause, bottomPauseS),
    TempoPhase(TempoPhaseKind.concentric, concentricS ?? concentricXS),
    if (topPauseS > 0) TempoPhase(TempoPhaseKind.topPause, topPauseS),
  ];

  double cycleSeconds(double concentricXS) =>
      phases(concentricXS).fold(0.0, (sum, phase) => sum + phase.seconds);
}

class TempoParams {
  const TempoParams({
    required this.minEccentricS,
    required this.concentricXS,
    required this.debounceMs,
  });

  factory TempoParams.fromAssumptions(Assumptions a) => TempoParams(
    minEccentricS: a[A.tempoMinEccentricS],
    concentricXS: a[A.tempoConcentricXS],
    debounceMs: a.integer(A.tapDebounceMs),
  );

  final double minEccentricS;
  final double concentricXS;
  final int debounceMs;
}

/// Where the metronome is at a given moment.
class MetronomePosition {
  const MetronomePosition({
    required this.repIndex,
    required this.phaseIndex,
    required this.phase,
    required this.phaseElapsedS,
  });

  final int repIndex;
  final int phaseIndex;
  final TempoPhase phase;
  final double phaseElapsedS;

  double get phaseRemainingS => phase.seconds - phaseElapsedS;
}

/// Metronome position [elapsedMs] after the set started.
MetronomePosition metronomeAt(
  TempoSpec spec,
  int elapsedMs,
  double concentricXS,
) {
  final phases = spec.phases(concentricXS);
  final cycle = spec.cycleSeconds(concentricXS);
  final seconds = elapsedMs < 0 ? 0.0 : elapsedMs / 1000;
  final rep = cycle <= 0 ? 0 : (seconds / cycle).floor();
  var within = cycle <= 0 ? 0.0 : seconds - rep * cycle;
  for (var i = 0; i < phases.length; i++) {
    if (within < phases[i].seconds || i == phases.length - 1) {
      return MetronomePosition(
        repIndex: rep,
        phaseIndex: i,
        phase: phases[i],
        phaseElapsedS: within,
      );
    }
    within -= phases[i].seconds;
  }
  return MetronomePosition(
    repIndex: rep,
    phaseIndex: 0,
    phase: phases.first,
    phaseElapsedS: 0,
  );
}

class RepAnalysis {
  const RepAnalysis({
    required this.tapsMs,
    required this.repDurationsS,
    required this.eccentricEstimatesS,
    required this.valid,
    required this.tutS,
  });

  /// Taps kept after debouncing, in ms since set start.
  final List<int> tapsMs;
  final List<double> repDurationsS;
  final List<double> eccentricEstimatesS;
  final List<bool> valid;
  final double tutS;

  int get reps => tapsMs.length;
  int get validReps => valid.where((v) => v).length;
}

/// Removes taps closer than [debounceMs] to the previous kept tap and
/// ignores taps before the set started.
List<int> debounceTaps(List<int> tapsMs, int debounceMs) {
  final sorted = tapsMs.where((t) => t >= 0).toList()..sort();
  final kept = <int>[];
  for (final tap in sorted) {
    if (kept.isEmpty || tap - kept.last >= debounceMs) kept.add(tap);
  }
  return kept;
}

/// Analyses [tapsMs] (ms since the set started) against [spec].
RepAnalysis analyzeReps(List<int> tapsMs, TempoSpec spec, TempoParams params) {
  final taps = debounceTaps(tapsMs, params.debounceMs);
  final concentric = spec.concentricS ?? params.concentricXS;
  final durations = <double>[];
  final eccentric = <double>[];
  final valid = <bool>[];
  var previous = 0;
  for (var i = 0; i < taps.length; i++) {
    final span = (taps[i] - previous) / 1000;
    previous = taps[i];
    final top = i == 0 ? 0.0 : spec.topPauseS;
    final estimate = span - spec.bottomPauseS - concentric - top;
    durations.add(span);
    eccentric.add(estimate);
    valid.add(estimate + 1e-9 >= params.minEccentricS);
  }
  return RepAnalysis(
    tapsMs: List.unmodifiable(taps),
    repDurationsS: List.unmodifiable(durations),
    eccentricEstimatesS: List.unmodifiable(eccentric),
    valid: List.unmodifiable(valid),
    tutS: taps.isEmpty ? 0 : taps.last / 1000,
  );
}
