import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/user_db.dart';
import '../../../telemetry/telemetry_repository.dart';
import 'targets.dart';

final telemetryRepositoryProvider =
    Provider<TelemetryRepository>((ref) => TelemetryRepository(ref.watch(userDbProvider)));

/// Health Connect samples of the last 70 days (60-day HRV baseline + week).
final telemetrySamplesProvider = StreamProvider<List<TelemetrySampleRow>>((ref) {
  final from = addDays(ref.watch(todayProvider), -70);
  return ref.watch(telemetryRepositoryProvider).watchSince(from);
});

final dailyTelemetryProvider = Provider<Map<DateTime, DailyTelemetry>>(
  (ref) => aggregateDaily(ref.watch(telemetrySamplesProvider).value ?? const []),
);

/// Recovery history: band data first, manual RHR (60 s palpation) as the
/// fallback, effort from the shift log.
final recoveryHistoryProvider = Provider<List<DailyRecovery>>((ref) {
  final telemetry = ref.watch(dailyTelemetryProvider);
  final metrics = ref.watch(bodyMetricsProvider).value ?? const <BodyMetricRow>[];
  final logs = ref.watch(dailyLogsProvider).value ?? const <DailyLogRow>[];
  final manualRhr = {
    for (final m in metrics)
      if (m.rhrBpm != null) parseIsoDate(m.date): m.rhrBpm!,
  };
  final effort = {
    for (final l in logs)
      if (l.workEffort != null) parseIsoDate(l.date): WorkEffort.parse(l.workEffort),
  };
  final days = {...telemetry.keys, ...manualRhr.keys, ...effort.keys};
  return [
    for (final d in days)
      DailyRecovery(
        date: d,
        hrvRmssdMs: telemetry[d]?.hrvRmssd,
        rhrBpm: telemetry[d]?.rhr ?? manualRhr[d],
        sleepMinutes: telemetry[d]?.sleepMinutes,
        workEffort: effort[d],
      ),
  ];
});

final readinessTodayProvider = Provider<ReadinessResult>((ref) {
  final params = ReadinessParams.fromAssumptions(ref.watch(currentAssumptionsProvider));
  return assessReadiness(
    ref.watch(recoveryHistoryProvider),
    today: ref.watch(todayProvider),
    params: params,
  );
});

/// Stores today's readiness in the `readiness` table (history).
Future<void> recordReadiness(WidgetRef ref) async {
  final result = ref.read(readinessTodayProvider);
  final today = ref.read(todayProvider);
  final telemetry = ref.read(dailyTelemetryProvider)[today];
  final db = ref.read(userDbProvider);
  final hrv = telemetry?.hrvRmssd;
  await db.into(db.readiness).insertOnConflictUpdate(ReadinessCompanion.insert(
        date: isoDate(today),
        hrvLnRmssd: Value(result.hrvShortMean ?? (hrv == null || hrv <= 0 ? null : math.log(hrv))),
        rhr: Value(result.rhrToday),
        sleepMin: Value(result.sleepLastNightMin),
        sleepSource: Value(result.sleepLastNightMin == null ? null : 'health_connect'),
        band: Value(result.band.code),
        reasons: Value(result.reasonsEs.join('\n')),
      ));
}
