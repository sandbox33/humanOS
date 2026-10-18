/// Daily readiness band (VERDE / AMARILLO / ROJO), capability-aware.
///
/// Each input is used only when it is available:
/// * HRV path when enough nightly/morning ln rMSSD exists: the 7-day mean
///   against the personal 60-day mean − 0.5 SD (smallest worthwhile change).
///   No fixed population baseline and never live "stress" alerts.
/// * Otherwise resting heart rate against the previous 28 days (> 1 SD).
/// * Sleep < 360 min, sleep debt > 5 h over 7 nights, a HIGH-effort shift,
///   a morning feel ≤ 2/5 and reps below the previous session in the last
///   session each add one AMARILLO flag.
/// Two or more flags make ROJO, which only *suggests* postponing 24 h; it
/// never blocks a session. Without any data the band is VERDE with a
/// "sin datos" note. Nights without data never count as debt. The result
/// lists every input with its status and confidence for the "?" sheet.
library;

import 'dart:math' as math;

import 'assumptions.dart';
import 'confidence.dart';
import 'day.dart';
import 'format_es.dart';

enum ReadinessBand {
  verde('VERDE'),
  amarillo('AMARILLO'),
  rojo('ROJO');

  const ReadinessBand(this.code);
  final String code;

  static ReadinessBand? parse(String? code) {
    for (final band in ReadinessBand.values) {
      if (band.code == code) return band;
    }
    return null;
  }
}

/// Self-reported shift effort stored in `daily_logs.work_effort`.
enum WorkEffort {
  off('OFF', 'LIBRE'),
  low('LOW', 'BAJO'),
  medium('MEDIUM', 'MEDIO'),
  high('HIGH', 'ALTO');

  const WorkEffort(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static WorkEffort? parse(String? code) {
    for (final effort in WorkEffort.values) {
      if (effort.code == code) return effort;
    }
    return null;
  }
}

/// Recovery data for one day. Sleep belongs to the night that ended on
/// [date] (wake-up day).
class DailyRecovery {
  const DailyRecovery({
    required this.date,
    this.hrvRmssdMs,
    this.rhrBpm,
    this.sleepMinutes,
    this.workEffort,
    this.morningFeel,
  });

  final DateTime date;
  final double? hrvRmssdMs;
  final double? rhrBpm;
  final double? sleepMinutes;
  final WorkEffort? workEffort;

  /// Morning 1-tap check-in, 1 (muy mal) … 5 (muy bien).
  final int? morningFeel;
}

/// What the device shares, from the `capabilities` table. Null means the
/// probe has not run yet (treated as "maybe").
class ReadinessCapabilities {
  const ReadinessCapabilities({this.hrv, this.restingHr, this.sleep});

  final bool? hrv;
  final bool? restingHr;
  final bool? sleep;
}

class ReadinessParams {
  const ReadinessParams({
    required this.hrvShortDays,
    required this.hrvLongDays,
    required this.hrvSdFactor,
    required this.hrvMinShortSamples,
    required this.hrvMinLongSamples,
    required this.rhrBaselineDays,
    required this.rhrSdFactor,
    required this.rhrMinBaselineSamples,
    required this.sleepMinMinutes,
    required this.sleepTargetH,
    required this.sleepDebtMaxH,
    required this.sleepDebtNights,
    required this.feelLowThreshold,
  });

  factory ReadinessParams.fromAssumptions(Assumptions a) => ReadinessParams(
    hrvShortDays: a.integer(A.hrvShortDays),
    hrvLongDays: a.integer(A.hrvLongDays),
    hrvSdFactor: a[A.hrvSdFactor],
    hrvMinShortSamples: a.integer(A.hrvMinShortSamples),
    hrvMinLongSamples: a.integer(A.hrvMinLongSamples),
    rhrBaselineDays: a.integer(A.rhrBaselineDays),
    rhrSdFactor: a[A.rhrSdFactor],
    rhrMinBaselineSamples: a.integer(A.rhrMinBaselineSamples),
    sleepMinMinutes: a[A.sleepMinMinutes],
    sleepTargetH: a[A.sleepTargetH],
    sleepDebtMaxH: a[A.sleepDebtMaxH],
    sleepDebtNights: a.integer(A.sleepDebtNights),
    feelLowThreshold: a.integer(A.feelLowThreshold),
  );

  final int hrvShortDays;
  final int hrvLongDays;
  final double hrvSdFactor;
  final int hrvMinShortSamples;
  final int hrvMinLongSamples;
  final int rhrBaselineDays;
  final double rhrSdFactor;
  final int rhrMinBaselineSamples;
  final double sleepMinMinutes;
  final double sleepTargetH;
  final double sleepDebtMaxH;
  final int sleepDebtNights;
  final int feelLowThreshold;
}

/// Which physiological signal drove the cardiac part of the assessment.
enum ReadinessPath { hrv, rhr, none }

/// Identifiers of AMARILLO flags.
enum ReadinessFlag {
  hrvLow,
  rhrHigh,
  shortSleep,
  highEffort,
  sleepDebt,
  lowFeel,
  performanceDrop,
}

/// Inputs shown in the "?" sheet.
enum ReadinessInputKind {
  hrv('VFC'),
  restingHr('FC en reposo'),
  sleep('Sueño'),
  sleepDebt('Deuda de sueño'),
  effort('Esfuerzo del turno'),
  feel('Sensación matinal'),
  performance('Rendimiento');

  const ReadinessInputKind(this.labelEs);
  final String labelEs;
}

enum ReadinessInputStatus {
  /// Data present and evaluated.
  used,

  /// The device can share it but there is no recent data.
  missing,

  /// The device does not share it (capability probe).
  unavailable,
}

class ReadinessInput {
  const ReadinessInput({
    required this.kind,
    required this.status,
    required this.detailEs,
    required this.confidence,
    this.flagged = false,
  });

  final ReadinessInputKind kind;
  final ReadinessInputStatus status;

  /// "VFC: no disponible con tu dispositivo", "Sueño: 7 h 10 min", …
  final String detailEs;
  final Confidence confidence;
  final bool flagged;
}

class ReadinessResult {
  const ReadinessResult({
    required this.band,
    required this.flags,
    required this.reasonsEs,
    required this.path,
    required this.noData,
    required this.inputs,
    required this.confidence,
    this.hrvShortMean,
    this.hrvLongMean,
    this.hrvLongSd,
    this.rhrToday,
    this.rhrMean,
    this.rhrSd,
    this.sleepLastNightMin,
    this.sleepDebtH,
  });

  final ReadinessBand band;
  final List<ReadinessFlag> flags;
  final List<String> reasonsEs;
  final ReadinessPath path;
  final bool noData;

  /// Every input with its status, for the "?" sheet.
  final List<ReadinessInput> inputs;
  final Confidence confidence;
  final double? hrvShortMean;
  final double? hrvLongMean;
  final double? hrvLongSd;
  final double? rhrToday;
  final double? rhrMean;
  final double? rhrSd;
  final double? sleepLastNightMin;
  final double? sleepDebtH;

  /// ROJO suggests postponing the session 24 h. It is a suggestion only.
  bool get suggestPostpone => band == ReadinessBand.rojo;

  ReadinessInput? input(ReadinessInputKind kind) {
    for (final i in inputs) {
      if (i.kind == kind) return i;
    }
    return null;
  }
}

double _mean(List<double> values) =>
    values.reduce((a, b) => a + b) / values.length;

/// Sample standard deviation (n − 1). Zero for fewer than two values.
double sampleSd(List<double> values) {
  if (values.length < 2) return 0;
  final m = _mean(values);
  var sum = 0.0;
  for (final v in values) {
    sum += (v - m) * (v - m);
  }
  return math.sqrt(sum / (values.length - 1));
}

String _notAvailable(ReadinessInputKind kind) =>
    '${kind.labelEs}: no disponible con tu dispositivo';

String _noRecentData(ReadinessInputKind kind) =>
    '${kind.labelEs}: sin datos recientes';

/// Assesses readiness for [today] from [history] (any order).
///
/// [performanceDrop] is true when the last session had fewer valid reps
/// than the previous one on its exercises, false when it did not, null
/// when there are not two comparable sessions.
ReadinessResult assessReadiness(
  List<DailyRecovery> history, {
  required DateTime today,
  required ReadinessParams params,
  ReadinessCapabilities capabilities = const ReadinessCapabilities(),
  bool? performanceDrop,
}) {
  final day = dateOnly(today);
  final byDate = <DateTime, DailyRecovery>{
    for (final r in history) dateOnly(r.date): r,
  };
  final todayRecord = byDate[day];
  final flags = <ReadinessFlag>[];
  final reasons = <String>[];
  final inputs = <ReadinessInput>[];
  var anyData = false;

  List<double> collect(
    int fromOffset,
    int toOffset,
    double? Function(DailyRecovery) pick,
  ) {
    final values = <double>[];
    for (var offset = fromOffset; offset <= toOffset; offset++) {
      final record = byDate[addDays(day, -offset)];
      final value = record == null ? null : pick(record);
      if (value != null) values.add(value);
    }
    return values;
  }

  double? lnRmssd(DailyRecovery r) {
    final v = r.hrvRmssdMs;
    return v == null || v <= 0 ? null : math.log(v);
  }

  // Cardiac signal: HRV when available, otherwise resting heart rate.
  var path = ReadinessPath.none;
  double? hrvShortMean, hrvLongMean, hrvLongSd;
  double? rhrToday, rhrMean, rhrSd;
  final shortHrv = collect(0, params.hrvShortDays - 1, lnRmssd);
  final longHrv = collect(0, params.hrvLongDays - 1, lnRmssd);
  if (shortHrv.length >= params.hrvMinShortSamples &&
      longHrv.length >= params.hrvMinLongSamples) {
    path = ReadinessPath.hrv;
    anyData = true;
    hrvShortMean = _mean(shortHrv);
    hrvLongMean = _mean(longHrv);
    hrvLongSd = sampleSd(longHrv);
    final lower = hrvLongMean - params.hrvSdFactor * hrvLongSd;
    final low = hrvShortMean < lower;
    if (low) {
      flags.add(ReadinessFlag.hrvLow);
      reasons.add(
        'VFC (ln rMSSD, media de ${params.hrvShortDays} días) por '
        'debajo de tu rango normal: ${formatDecimal(hrvShortMean, decimals: 2)} '
        'frente a ${formatDecimal(hrvLongMean, decimals: 2)} − '
        '${formatDecimal(params.hrvSdFactor)} DE.',
      );
    }
    inputs.add(
      ReadinessInput(
        kind: ReadinessInputKind.hrv,
        status: ReadinessInputStatus.used,
        detailEs:
            'VFC: media de ${params.hrvShortDays} días '
            '${formatDecimal(hrvShortMean, decimals: 2)} (ln rMSSD), tu base '
            'de ${params.hrvLongDays} días '
            '${formatDecimal(hrvLongMean, decimals: 2)}.',
        confidence: Confidence.media,
        flagged: low,
      ),
    );
  } else {
    final hrvAvailable = capabilities.hrv != false || longHrv.isNotEmpty;
    inputs.add(
      ReadinessInput(
        kind: ReadinessInputKind.hrv,
        status: hrvAvailable
            ? ReadinessInputStatus.missing
            : ReadinessInputStatus.unavailable,
        detailEs: hrvAvailable
            ? 'VFC: faltan noches con dato (${longHrv.length} de '
                  '${params.hrvMinLongSamples} necesarias).'
            : _notAvailable(ReadinessInputKind.hrv),
        confidence: Confidence.baja,
      ),
    );

    rhrToday = todayRecord?.rhrBpm;
    final baseline = collect(1, params.rhrBaselineDays, (r) => r.rhrBpm);
    if (rhrToday != null) anyData = true;
    if (rhrToday != null && baseline.length >= params.rhrMinBaselineSamples) {
      path = ReadinessPath.rhr;
      rhrMean = _mean(baseline);
      rhrSd = sampleSd(baseline);
      final high = rhrToday > rhrMean + params.rhrSdFactor * rhrSd;
      if (high) {
        flags.add(ReadinessFlag.rhrHigh);
        reasons.add(
          'FC en reposo elevada: ${formatWhole(rhrToday)} lpm frente '
          'a tu media de ${formatWhole(rhrMean)} ± '
          '${formatDecimal(rhrSd)} lpm.',
        );
      }
      inputs.add(
        ReadinessInput(
          kind: ReadinessInputKind.restingHr,
          status: ReadinessInputStatus.used,
          detailEs:
              'FC en reposo: ${formatWhole(rhrToday)} lpm; tu media de '
              '${params.rhrBaselineDays} días es ${formatWhole(rhrMean)} lpm.',
          confidence: Confidence.baja,
          flagged: high,
        ),
      );
    } else {
      final rhrAvailable =
          capabilities.restingHr != false ||
          rhrToday != null ||
          baseline.isNotEmpty;
      inputs.add(
        ReadinessInput(
          kind: ReadinessInputKind.restingHr,
          status: rhrAvailable
              ? ReadinessInputStatus.missing
              : ReadinessInputStatus.unavailable,
          detailEs: rhrAvailable
              ? (rhrToday == null
                    ? _noRecentData(ReadinessInputKind.restingHr)
                    : 'FC en reposo: faltan días para tu base '
                          '(${baseline.length} de '
                          '${params.rhrMinBaselineSamples}).')
              : _notAvailable(ReadinessInputKind.restingHr),
          confidence: Confidence.baja,
        ),
      );
    }
  }

  final sleepLastNight = todayRecord?.sleepMinutes;
  if (sleepLastNight != null) {
    anyData = true;
    final short = sleepLastNight < params.sleepMinMinutes;
    if (short) {
      flags.add(ReadinessFlag.shortSleep);
      reasons.add(
        'Dormiste ${formatHoursMinutes(sleepLastNight)} '
        '(menos de ${formatHoursMinutes(params.sleepMinMinutes)}).',
      );
    }
    inputs.add(
      ReadinessInput(
        kind: ReadinessInputKind.sleep,
        status: ReadinessInputStatus.used,
        detailEs: 'Sueño: ${formatHoursMinutes(sleepLastNight)} anoche.',
        confidence: Confidence.media,
        flagged: short,
      ),
    );
  } else {
    inputs.add(
      ReadinessInput(
        kind: ReadinessInputKind.sleep,
        status: capabilities.sleep == false
            ? ReadinessInputStatus.unavailable
            : ReadinessInputStatus.missing,
        detailEs: capabilities.sleep == false
            ? _notAvailable(ReadinessInputKind.sleep)
            : 'Sueño: sin dato de anoche.',
        confidence: Confidence.baja,
      ),
    );
  }

  double? debtH;
  final nights = collect(0, params.sleepDebtNights - 1, (r) => r.sleepMinutes);
  if (nights.isNotEmpty) {
    debtH = nights
        .map((m) => params.sleepTargetH - m / 60)
        .reduce((a, b) => a + b);
    final inDebt = debtH > params.sleepDebtMaxH;
    if (inDebt) {
      flags.add(ReadinessFlag.sleepDebt);
      reasons.add(
        'Deuda de sueño de ${formatDecimal(debtH)} h en las últimas '
        '${nights.length} noches con registro.',
      );
    }
    inputs.add(
      ReadinessInput(
        kind: ReadinessInputKind.sleepDebt,
        status: ReadinessInputStatus.used,
        detailEs:
            'Deuda de sueño: ${formatDecimal(debtH)} h en '
            '${nights.length} noches con registro.',
        confidence: Confidence.media,
        flagged: inDebt,
      ),
    );
  } else {
    inputs.add(
      ReadinessInput(
        kind: ReadinessInputKind.sleepDebt,
        status: capabilities.sleep == false
            ? ReadinessInputStatus.unavailable
            : ReadinessInputStatus.missing,
        detailEs: capabilities.sleep == false
            ? _notAvailable(ReadinessInputKind.sleepDebt)
            : _noRecentData(ReadinessInputKind.sleepDebt),
        confidence: Confidence.baja,
      ),
    );
  }

  final effort = todayRecord?.workEffort;
  if (effort != null) {
    anyData = true;
    final high = effort == WorkEffort.high;
    if (high) {
      flags.add(ReadinessFlag.highEffort);
      reasons.add('Turno de esfuerzo ALTO hoy.');
    }
    inputs.add(
      ReadinessInput(
        kind: ReadinessInputKind.effort,
        status: ReadinessInputStatus.used,
        detailEs: 'Esfuerzo del turno: ${effort.labelEs}.',
        confidence: Confidence.alta,
        flagged: high,
      ),
    );
  } else {
    inputs.add(
      const ReadinessInput(
        kind: ReadinessInputKind.effort,
        status: ReadinessInputStatus.missing,
        detailEs: 'Esfuerzo del turno: sin registrar hoy.',
        confidence: Confidence.baja,
      ),
    );
  }

  final feel = todayRecord?.morningFeel;
  if (feel != null && feel >= 1 && feel <= 5) {
    anyData = true;
    final low = feel <= params.feelLowThreshold;
    if (low) {
      flags.add(ReadinessFlag.lowFeel);
      reasons.add('Amaneciste con $feel/5.');
    }
    inputs.add(
      ReadinessInput(
        kind: ReadinessInputKind.feel,
        status: ReadinessInputStatus.used,
        detailEs: 'Sensación matinal: $feel/5.',
        confidence: Confidence.alta,
        flagged: low,
      ),
    );
  } else {
    inputs.add(
      const ReadinessInput(
        kind: ReadinessInputKind.feel,
        status: ReadinessInputStatus.missing,
        detailEs: 'Sensación matinal: sin responder hoy.',
        confidence: Confidence.baja,
      ),
    );
  }

  if (performanceDrop != null) {
    anyData = true;
    if (performanceDrop) {
      flags.add(ReadinessFlag.performanceDrop);
      reasons.add(
        'En tu última sesión hiciste menos repeticiones válidas que en la '
        'anterior.',
      );
    }
    inputs.add(
      ReadinessInput(
        kind: ReadinessInputKind.performance,
        status: ReadinessInputStatus.used,
        detailEs: performanceDrop
            ? 'Rendimiento: la última sesión quedó por debajo de la anterior.'
            : 'Rendimiento: la última sesión igualó o superó a la anterior.',
        confidence: Confidence.alta,
        flagged: performanceDrop,
      ),
    );
  } else {
    inputs.add(
      const ReadinessInput(
        kind: ReadinessInputKind.performance,
        status: ReadinessInputStatus.missing,
        detailEs: 'Rendimiento: faltan dos sesiones comparables.',
        confidence: Confidence.baja,
      ),
    );
  }

  final used = inputs
      .where((i) => i.status == ReadinessInputStatus.used)
      .length;
  final confidence = !anyData || used <= 1
      ? Confidence.baja
      : (path == ReadinessPath.hrv && used >= 4
            ? Confidence.alta
            : Confidence.media);

  if (!anyData) {
    return ReadinessResult(
      band: ReadinessBand.verde,
      flags: const [],
      reasonsEs: const ['Sin datos de recuperación: se asume VERDE.'],
      path: ReadinessPath.none,
      noData: true,
      inputs: List.unmodifiable(inputs),
      confidence: Confidence.baja,
    );
  }

  final band = switch (flags.length) {
    0 => ReadinessBand.verde,
    1 => ReadinessBand.amarillo,
    _ => ReadinessBand.rojo,
  };
  if (band == ReadinessBand.rojo) {
    reasons.add(
      'Se sugiere posponer la sesión 24 h. Puedes entrenar igual: '
      'quedará registrado.',
    );
  }
  if (band == ReadinessBand.verde) {
    reasons.add('Sin señales de fatiga en los datos disponibles.');
  }
  return ReadinessResult(
    band: band,
    flags: List.unmodifiable(flags),
    reasonsEs: List.unmodifiable(reasons),
    path: path,
    noData: false,
    inputs: List.unmodifiable(inputs),
    confidence: confidence,
    hrvShortMean: hrvShortMean,
    hrvLongMean: hrvLongMean,
    hrvLongSd: hrvLongSd,
    rhrToday: rhrToday,
    rhrMean: rhrMean,
    rhrSd: rhrSd,
    sleepLastNightMin: sleepLastNight,
    sleepDebtH: debtH,
  );
}
