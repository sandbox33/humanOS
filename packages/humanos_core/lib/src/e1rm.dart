/// Estimated one-repetition maximum (Epley) and personal-record detection.
library;

/// Divisor of the Epley formula `load × (1 + reps / 30)` (Epley 1985). It
/// is part of the formula's definition, not a tunable assumption.
const double epleyDivisor = 30;

/// Epley e1RM; null when no repetition was completed.
double? epleyE1rm(double loadKg, int reps) {
  if (reps <= 0 || loadKg <= 0) return null;
  return loadKg * (1 + reps / epleyDivisor);
}

/// A previous working set (load and valid reps).
class LiftResult {
  const LiftResult({required this.loadKg, required this.reps});
  final double loadKg;
  final int reps;
}

class PrCheck {
  const PrCheck({
    required this.e1rm,
    required this.previousBestE1rm,
    required this.isE1rmPr,
    required this.previousBestRepsAtLoad,
    required this.isRepsAtLoadPr,
  });

  final double? e1rm;
  final double? previousBestE1rm;
  final bool isE1rmPr;

  /// Most reps ever done at this load or heavier.
  final int? previousBestRepsAtLoad;
  final bool isRepsAtLoadPr;

  bool get any => isE1rmPr || isRepsAtLoadPr;
}

/// Compares a new set with [previous] sets of the same exercise.
///
/// e1RM PR: strictly above every previous e1RM. Reps-at-load PR: more reps
/// than any previous set at the same or a heavier load. The first set ever
/// is not a PR (nothing to beat).
PrCheck checkPr({
  required double loadKg,
  required int reps,
  required List<LiftResult> previous,
}) {
  final e1rm = epleyE1rm(loadKg, reps);
  double? bestE1rm;
  int? bestRepsAtLoad;
  for (final p in previous) {
    final value = epleyE1rm(p.loadKg, p.reps);
    if (value != null && (bestE1rm == null || value > bestE1rm)) {
      bestE1rm = value;
    }
    if (p.loadKg >= loadKg &&
        (bestRepsAtLoad == null || p.reps > bestRepsAtLoad)) {
      bestRepsAtLoad = p.reps;
    }
  }
  final hasHistory = previous.isNotEmpty;
  return PrCheck(
    e1rm: e1rm,
    previousBestE1rm: bestE1rm,
    isE1rmPr:
        hasHistory &&
        e1rm != null &&
        (bestE1rm == null || e1rm > bestE1rm + 1e-9),
    previousBestRepsAtLoad: bestRepsAtLoad,
    isRepsAtLoadPr:
        hasHistory &&
        reps > 0 &&
        (bestRepsAtLoad == null || reps > bestRepsAtLoad),
  );
}
