import 'package:drift/drift.dart';
import 'package:humanos_core/humanos_core.dart';

import '../data/user_db.dart';
import 'confidence.dart';

class TelemetryRepository {
  TelemetryRepository(this._db);
  final UserDb _db;

  Future<int> upsert(List<TelemetrySample> samples) async {
    if (samples.isEmpty) return 0;
    await _db.batch((b) {
      b.insertAll(
        _db.telemetrySamples,
        [
          for (final s in samples)
            TelemetrySamplesCompanion.insert(
              type: s.type,
              start: s.start.toIso8601String(),
              end: Value(s.end?.toIso8601String()),
              value: Value(s.value),
              source: s.source,
            ),
        ],
        mode: InsertMode.insertOrReplace,
      );
    });
    return samples.length;
  }

  Stream<List<TelemetrySampleRow>> watchSince(DateTime from) =>
      (_db.select(_db.telemetrySamples)
            ..where((t) => t.start.isBiggerOrEqualValue(from.toIso8601String())))
          .watch();

  Future<List<TelemetrySampleRow>> since(DateTime from) =>
      (_db.select(_db.telemetrySamples)
            ..where((t) => t.start.isBiggerOrEqualValue(from.toIso8601String())))
          .get();
}

/// Per-day aggregates used by readiness and attributes.
class DailyTelemetry {
  const DailyTelemetry({this.rhr, this.hrvRmssd, this.sleepMinutes, this.steps});
  final double? rhr;
  final double? hrvRmssd;
  final double? sleepMinutes;
  final double? steps;
}

const _asleepStages = {'SLEEP_ASLEEP', 'SLEEP_DEEP', 'SLEEP_LIGHT', 'SLEEP_REM'};

/// Aggregates raw samples by calendar day. Sleep belongs to the day the
/// night ended; stages are used only when there is no session record.
Map<DateTime, DailyTelemetry> aggregateDaily(List<TelemetrySampleRow> rows) {
  final rhr = <DateTime, List<double>>{};
  final hrv = <DateTime, List<double>>{};
  final sessions = <DateTime, double>{};
  final stages = <DateTime, double>{};
  final steps = <DateTime, double>{};
  for (final r in rows) {
    final value = r.value;
    if (value == null) continue;
    final start = DateTime.tryParse(r.start);
    if (start == null) continue;
    final end = r.end == null ? start : (DateTime.tryParse(r.end!) ?? start);
    final startDay = dateOnly(start);
    final endDay = dateOnly(end);
    switch (r.type) {
      case 'RESTING_HEART_RATE':
        (rhr[startDay] ??= []).add(value);
      case 'HEART_RATE_VARIABILITY_RMSSD':
        (hrv[startDay] ??= []).add(value);
      case 'SLEEP_SESSION':
        sessions[endDay] = (sessions[endDay] ?? 0) + value;
      case 'STEPS':
        steps[startDay] = (steps[startDay] ?? 0) + value;
      default:
        if (_asleepStages.contains(r.type)) {
          stages[endDay] = (stages[endDay] ?? 0) + value;
        }
    }
  }
  double? mean(List<double>? v) =>
      v == null || v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  final days = {...rhr.keys, ...hrv.keys, ...sessions.keys, ...stages.keys, ...steps.keys};
  return {
    for (final d in days)
      d: DailyTelemetry(
        rhr: mean(rhr[d]),
        hrvRmssd: mean(hrv[d]),
        sleepMinutes: sessions[d] ?? stages[d],
        steps: steps[d],
      ),
  };
}

/// Which kinds returned data since a date (diagnosis screen).
Map<TelemetryKind, int> countByKind(List<TelemetrySampleRow> rows) {
  final counts = <TelemetryKind, int>{};
  for (final r in rows) {
    final kind = TelemetryKind.ofCode(r.type);
    if (kind != null) counts[kind] = (counts[kind] ?? 0) + 1;
  }
  return counts;
}
