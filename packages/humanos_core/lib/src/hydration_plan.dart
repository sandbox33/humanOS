/// Shift hydration plan. Replaces the sweat-rate test.
///
/// The base range follows NIOSH heat guidance: one cup (0.24 L) every
/// 15–20 min of heat exposure, i.e. 0.72–0.96 L/h, never above the hourly
/// cap. It is scaled by the mean factor of the self-reported sweat of the
/// last days (poco ×0.8, normal ×1, mucho ×1.2). It is a range, not a
/// prescription: sweat changes with weather and task.
///
/// Only two reminders exist, both outside welding time: before the shift
/// ("llena el termo") and at the lunch break. Electrolytes are text only.
library;

import 'assumptions.dart';
import 'confidence.dart';
import 'day.dart';
import 'format_es.dart';

/// Self-reported sweat after a shift (`daily_logs.sweat_feel`).
enum SweatFeel {
  poco('poco', 'POCO'),
  normal('normal', 'NORMAL'),
  mucho('mucho', 'MUCHO');

  const SweatFeel(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static SweatFeel? parse(String? code) {
    for (final feel in SweatFeel.values) {
      if (feel.code == code) return feel;
    }
    return null;
  }
}

class SweatFeelEntry {
  const SweatFeelEntry({required this.date, required this.feel});
  final DateTime date;
  final SweatFeel feel;
}

class HydrationParams {
  const HydrationParams({
    required this.cupL,
    required this.intervalShortMin,
    required this.intervalLongMin,
    required this.capLPerH,
    required this.pocoFactor,
    required this.normalFactor,
    required this.muchoFactor,
    required this.feelDays,
    required this.preShiftLeadMin,
  });

  factory HydrationParams.fromAssumptions(Assumptions a) => HydrationParams(
    cupL: a[A.heatBolusL],
    intervalShortMin: a[A.heatBolusIntervalMinMin],
    intervalLongMin: a[A.heatBolusIntervalMaxMin],
    capLPerH: a[A.fluidCapLPerH],
    pocoFactor: a[A.sweatFeelPocoFactor],
    normalFactor: a[A.sweatFeelNormalFactor],
    muchoFactor: a[A.sweatFeelMuchoFactor],
    feelDays: a.integer(A.sweatFeelDays),
    preShiftLeadMin: a.integer(A.hydrationPreShiftLeadMin),
  );

  final double cupL;
  final double intervalShortMin;
  final double intervalLongMin;
  final double capLPerH;
  final double pocoFactor;
  final double normalFactor;
  final double muchoFactor;
  final int feelDays;
  final int preShiftLeadMin;

  double factorFor(SweatFeel feel) => switch (feel) {
    SweatFeel.poco => pocoFactor,
    SweatFeel.normal => normalFactor,
    SweatFeel.mucho => muchoFactor,
  };
}

/// Mean sweat factor over the window and what it was built from.
class SweatFactor {
  const SweatFactor({
    required this.factor,
    required this.daysUsed,
    required this.muchoDays,
  });

  /// Normal factor when there is no data.
  final double factor;
  final int daysUsed;
  final int muchoDays;
}

/// Mean factor of the entries within the last [HydrationParams.feelDays]
/// days up to [today] (inclusive). Without entries the normal factor is
/// used and [SweatFactor.daysUsed] is 0.
SweatFactor sweatFactor(
  List<SweatFeelEntry> history, {
  required DateTime today,
  required HydrationParams params,
}) {
  final end = dateOnly(today);
  final start = addDays(end, -(params.feelDays - 1));
  final byDay = <DateTime, SweatFeel>{};
  for (final entry in history) {
    final day = dateOnly(entry.date);
    if (day.isBefore(start) || day.isAfter(end)) continue;
    byDay[day] = entry.feel;
  }
  if (byDay.isEmpty) {
    return SweatFactor(factor: params.normalFactor, daysUsed: 0, muchoDays: 0);
  }
  final sum = byDay.values.map(params.factorFor).reduce((a, b) => a + b);
  return SweatFactor(
    factor: sum / byDay.length,
    daysUsed: byDay.length,
    muchoDays: byDay.values.where((f) => f == SweatFeel.mucho).length,
  );
}

/// Electrolyte guidance. Text only: no doses are computed.
const String electrolyteNoteEs =
    'Si sudas mucho, añade sal o electrolitos a 1 termo.';

class HydrationPlan {
  const HydrationPlan({
    required this.heatHours,
    required this.lPerHMin,
    required this.lPerHMax,
    required this.factor,
    required this.capped,
    required this.confidence,
    required this.highlightElectrolytes,
  });

  final double heatHours;
  final double lPerHMin;
  final double lPerHMax;
  final SweatFactor factor;

  /// The hourly cap lowered the upper end.
  final bool capped;
  final Confidence confidence;

  /// Recent shifts were marked "mucho": show [electrolyteNoteEs] first.
  final bool highlightElectrolytes;

  bool get hasHeat => heatHours > 0;
  double get totalLMin => lPerHMin * heatHours;
  double get totalLMax => lPerHMax * heatHours;

  /// "5,8–7,7 L"
  String get rangeEs =>
      '${formatDecimal(totalLMin)}–${formatDecimal(totalLMax)} L';

  String get summaryEs {
    if (!hasHeat) {
      return 'Sin horas de calor declaradas: bebe según tu sed.';
    }
    final perHour =
        '${formatDecimal(lPerHMin, decimals: 2)}–'
        '${formatDecimal(lPerHMax, decimals: 2)} L/h';
    return 'Termo para hoy: $rangeEs en ${formatDecimal(heatHours)} h de '
        'calor ($perHour).';
  }

  /// How the range was built, for the "?" sheet.
  String get basisEs {
    final f = factor;
    final feel = f.daysUsed == 0
        ? 'Sin registros de sudor recientes: factor normal '
              '(${formatDecimal(f.factor)}).'
        : 'Factor ${formatDecimal(f.factor, decimals: 2)} según lo que '
              'marcaste en ${f.daysUsed} '
              '${f.daysUsed == 1 ? 'turno' : 'turnos'}.';
    final cap = capped ? ' El tope por hora recortó el extremo alto.' : '';
    return 'Base: una taza cada 15–20 min de calor (guía NIOSH). $feel$cap';
  }
}

/// Builds the plan for [heatHours] of heat exposure today.
HydrationPlan hydrationPlan({
  required double heatHours,
  required List<SweatFeelEntry> feelHistory,
  required DateTime today,
  required HydrationParams params,
}) {
  final hours = heatHours.isFinite && heatHours > 0 ? heatHours : 0.0;
  final f = sweatFactor(feelHistory, today: today, params: params);
  final baseMin = params.cupL * 60 / params.intervalLongMin;
  final baseMax = params.cupL * 60 / params.intervalShortMin;
  final rawMin = baseMin * f.factor;
  final rawMax = baseMax * f.factor;
  final min = rawMin > params.capLPerH ? params.capLPerH : rawMin;
  final max = rawMax > params.capLPerH ? params.capLPerH : rawMax;
  return HydrationPlan(
    heatHours: hours,
    lPerHMin: min,
    lPerHMax: max,
    factor: f,
    capped: rawMax > params.capLPerH,
    confidence: f.daysUsed == 0 ? Confidence.baja : Confidence.media,
    highlightElectrolytes: f.muchoDays > 0,
  );
}

/// The only two hydration reminders of a workday.
enum HydrationReminderKind {
  preShift('pre_shift'),
  lunch('lunch');

  const HydrationReminderKind(this.code);
  final String code;
}

class HydrationReminder {
  const HydrationReminder({
    required this.kind,
    required this.minuteOfDay,
    required this.titleEs,
    required this.bodyEs,
  });

  final HydrationReminderKind kind;

  /// Minutes since midnight (may be negative before a 00:xx shift start;
  /// callers wrap it to the previous day).
  final int minuteOfDay;
  final String titleEs;
  final String bodyEs;
}

/// Reminders for a workday: before the shift and at the start of lunch.
/// Nothing else is ever scheduled between shift start and end.
List<HydrationReminder> hydrationReminders({
  required int shiftStartMin,
  required int lunchStartMin,
  required HydrationPlan plan,
  required HydrationParams params,
}) {
  final electrolytes = plan.highlightElectrolytes ? ' $electrolyteNoteEs' : '';
  final range = plan.hasHeat ? plan.rangeEs : null;
  return [
    HydrationReminder(
      kind: HydrationReminderKind.preShift,
      minuteOfDay: shiftStartMin - params.preShiftLeadMin,
      titleEs: 'LLENA EL TERMO',
      bodyEs: range == null
          ? 'Entras a las ${formatClock(shiftStartMin)}. Lleva agua.'
          : 'Entras a las ${formatClock(shiftStartMin)}. Plan del turno: '
                '$range.$electrolytes',
    ),
    HydrationReminder(
      kind: HydrationReminderKind.lunch,
      minuteOfDay: lunchStartMin,
      titleEs: 'ALMUERZO: RELLENA EL TERMO',
      bodyEs: range == null
          ? 'Hora de comer. Rellena el agua para la tarde.'
          : 'Rellena el termo para la tarde. Plan del turno: $range.'
                '$electrolytes',
    ),
  ];
}
