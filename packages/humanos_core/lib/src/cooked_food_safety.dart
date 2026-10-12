/// Safety window for cooked food kept out of the fridge.
///
/// Refrigerated: normal storage (3–4 days). Ambient up to 32 °C: warn at
/// 2 h, discard at 4 h. Heat-exposed (workshop, lunchbox in the sun, above
/// 32 °C): discard at 1 h. The clock runs from cooking, not from the last
/// reheat: Bacillus cereus emetic toxin is heat-stable, so reheating does
/// not make food safe again.
library;

import 'assumptions.dart';
import 'format_es.dart';

enum SafetyLevel { ok, warn, discard }

class SafetyParams {
  const SafetyParams({
    required this.warnH,
    required this.discardH,
    required this.heatWarnH,
    required this.heatDiscardH,
    required this.fridgeDays,
  });

  factory SafetyParams.fromAssumptions(Assumptions a) => SafetyParams(
    warnH: a[A.cookedWarnH],
    discardH: a[A.cookedDiscardH],
    heatWarnH: a[A.cookedHeatWarnH],
    heatDiscardH: a[A.cookedHeatDiscardH],
    fridgeDays: a[A.fridgeLeftoverDays],
  );

  final double warnH;
  final double discardH;
  final double heatWarnH;
  final double heatDiscardH;
  final double fridgeDays;
}

class CookedBatchState {
  const CookedBatchState({
    required this.name,
    required this.level,
    required this.hoursElapsed,
    required this.deadline,
    required this.refrigerated,
    required this.heatExposed,
    required this.messageEs,
  });

  final String name;
  final SafetyLevel level;
  final double hoursElapsed;

  /// When the batch must be discarded.
  final DateTime deadline;
  final bool refrigerated;
  final bool heatExposed;
  final String messageEs;

  double hoursLeft(DateTime now) {
    final left = deadline.difference(now).inSeconds / 3600;
    return left < 0 ? 0 : left;
  }
}

/// Evaluates a cooked batch at [now].
CookedBatchState evaluateCookedBatch({
  required String name,
  required DateTime cookedAt,
  required DateTime now,
  required bool heatExposed,
  required bool refrigerated,
  required SafetyParams params,
}) {
  final hours = now.difference(cookedAt).inSeconds / 3600;
  final elapsed = hours < 0 ? 0.0 : hours;
  Duration hoursToDuration(double h) => Duration(seconds: (h * 3600).round());

  if (refrigerated && !heatExposed) {
    final deadline = cookedAt.add(hoursToDuration(params.fridgeDays * 24));
    final expired = !now.isBefore(deadline);
    return CookedBatchState(
      name: name,
      level: expired ? SafetyLevel.discard : SafetyLevel.ok,
      hoursElapsed: elapsed,
      deadline: deadline,
      refrigerated: true,
      heatExposed: false,
      messageEs: expired
          ? '$name: lleva más de ${formatWhole(params.fridgeDays)} días en la '
                'nevera. Deséchalo.'
          : '$name: refrigerado, conservación normal. Consúmelo en '
                '${formatWhole(params.fridgeDays)} días como máximo.',
    );
  }

  final warnAt = heatExposed ? params.heatWarnH : params.warnH;
  final discardAt = heatExposed ? params.heatDiscardH : params.discardH;
  final deadline = cookedAt.add(hoursToDuration(discardAt));
  final context = heatExposed ? ' al calor' : ' fuera de la nevera';
  if (elapsed >= discardAt) {
    return CookedBatchState(
      name: name,
      level: SafetyLevel.discard,
      hoursElapsed: elapsed,
      deadline: deadline,
      refrigerated: refrigerated,
      heatExposed: heatExposed,
      messageEs:
          '$name: ${formatDecimal(elapsed)} h$context. Pasó el margen '
          'seguro: deséchalo. Recalentar no elimina la toxina.',
    );
  }
  if (elapsed >= warnAt) {
    return CookedBatchState(
      name: name,
      level: SafetyLevel.warn,
      hoursElapsed: elapsed,
      deadline: deadline,
      refrigerated: refrigerated,
      heatExposed: heatExposed,
      messageEs:
          '$name: ${formatDecimal(elapsed)} h$context. Cómelo dentro '
          'de ${formatDecimal(discardAt - elapsed)} h o deséchalo.',
    );
  }
  return CookedBatchState(
    name: name,
    level: SafetyLevel.ok,
    hoursElapsed: elapsed,
    deadline: deadline,
    refrigerated: refrigerated,
    heatExposed: heatExposed,
    messageEs:
        '$name: ${formatDecimal(elapsed)} h — dentro del margen '
        'seguro (${formatDecimal(discardAt)} h$context).',
  );
}

/// Most urgent first: discard, then warn, then ok; older first in a level.
List<CookedBatchState> sortByUrgency(List<CookedBatchState> states) {
  int rank(SafetyLevel level) => switch (level) {
    SafetyLevel.discard => 0,
    SafetyLevel.warn => 1,
    SafetyLevel.ok => 2,
  };
  return [...states]..sort((a, b) {
    final byLevel = rank(a.level).compareTo(rank(b.level));
    return byLevel != 0 ? byLevel : b.hoursElapsed.compareTo(a.hoursElapsed);
  });
}
