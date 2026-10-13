import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/user_db.dart';
import '../../estado/domain/targets.dart';

/// Latest valid sweat test (rate in L/h) among the recent logs.
final latestSweatTestProvider = Provider<({double rate, String date})?>((ref) {
  final logs = ref.watch(dailyLogsProvider).value ?? const <DailyLogRow>[];
  for (final log in logs.reversed) {
    final pre = log.sweatPreKg, post = log.sweatPostKg, hours = log.heatHours;
    if (pre == null || post == null || hours == null || hours <= 0) continue;
    final rate = (pre - post + (log.fluidsL ?? 0) - (log.urineL ?? 0)) / hours;
    if (rate > 0) return (rate: rate, date: log.date);
  }
  return null;
});

HydrationPlan planFor(double heatHours, SweatParams params, double? rate) =>
    hydrationPlan(heatHours: heatHours, params: params, sweatRateLPerH: rate);

/// Today's thermos plan for the declared heat hours.
final hydrationPlanProvider = Provider<HydrationPlan>((ref) {
  final params = SweatParams.fromAssumptions(ref.watch(currentAssumptionsProvider));
  final log = ref.watch(todayLogProvider);
  return planFor(log?.heatHours ?? 0, params, ref.watch(latestSweatTestProvider)?.rate);
});

/// Planned litres for compliance: the middle of the plan's range.
double plannedLitres(HydrationPlan plan) => (plan.totalLMin + plan.totalLMax) / 2;

/// Fraction of the plan drunk today, or null without heat hours or fluids.
final hydrationComplianceProvider = Provider<double?>((ref) {
  final plan = ref.watch(hydrationPlanProvider);
  final fluids = ref.watch(todayLogProvider)?.fluidsL;
  final target = plannedLitres(plan);
  if (fluids == null || target <= 0) return null;
  return fluids / target;
});

/// Sodium lost in sweat today (upper end of the plan), for the day plan.
final sweatSodiumTodayProvider = Provider<double>((ref) {
  final plan = ref.watch(hydrationPlanProvider);
  return plan.heatHours > 0 ? plan.sodiumMgMax : 0;
});
