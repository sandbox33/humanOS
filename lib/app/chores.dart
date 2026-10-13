import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../data/settings.dart';
import '../data/user_db.dart';
import '../features/estado/domain/readiness_today.dart';
import '../features/estado/domain/targets.dart';
import '../features/heavy_duty/domain/training_plan.dart';
import '../services/services.dart';
import '../telemetry/confidence.dart';
import '../telemetry/health_connect_source.dart';
import 'providers.dart';

/// Outcome of a Health Connect read.
class HealthSyncResult {
  const HealthSyncResult({required this.ok, required this.samples, required this.messageEs});
  final bool ok;
  final int samples;
  final String messageEs;
}

/// Reads Health Connect since the last sync (overlapping two days for late
/// band uploads, at most 30 days back) and stores the samples. Weights fill
/// days without a manual weigh-in. Health data stays on the device.
Future<HealthSyncResult> syncHealth(WidgetRef ref) async {
  final source = ref.read(healthSourceProvider);
  if (source == null) {
    return const HealthSyncResult(
        ok: false, samples: 0, messageEs: 'Health Connect no está disponible aquí.');
  }
  try {
    final availability = await source.availability();
    if (availability == HealthAvailability.needsInstall) {
      return const HealthSyncResult(
          ok: false, samples: 0, messageEs: 'Instala o actualiza Health Connect.');
    }
    if (availability == HealthAvailability.unavailable) {
      return const HealthSyncResult(
          ok: false, samples: 0, messageEs: 'Health Connect no está disponible en este teléfono.');
    }
    final settings = ref.read(settingsRepositoryProvider);
    final now = ref.read(clockProvider)();
    final last = DateTime.tryParse(await settings.get(SettingKey.healthLastSync) ?? '');
    final oldest = now.subtract(const Duration(days: 30));
    var from = last == null ? oldest : last.subtract(const Duration(days: 2));
    if (from.isBefore(oldest)) from = oldest;
    final samples = await source.read(from, now);
    await ref.read(telemetryRepositoryProvider).upsert(samples);

    final weights = <String, (DateTime, double)>{};
    for (final s in samples) {
      final value = s.value;
      if (s.type != TelemetryKind.weight.code || value == null || value <= 0) continue;
      final day = isoDate(s.start);
      final current = weights[day];
      if (current == null || s.start.isAfter(current.$1)) weights[day] = (s.start, value);
    }
    final body = ref.read(bodyRepositoryProvider);
    for (final entry in weights.entries) {
      await body.importWeightIfMissing(entry.key, entry.value.$2);
    }
    await settings.set(SettingKey.healthLastSync, now.toIso8601String());
    return HealthSyncResult(
      ok: true,
      samples: samples.length,
      messageEs: samples.isEmpty
          ? 'Health Connect no devolvió datos nuevos.'
          : '${samples.length} lecturas guardadas en el teléfono.',
    );
  } on Object catch (e) {
    return HealthSyncResult(ok: false, samples: 0, messageEs: 'No se pudo leer Health Connect: $e');
  }
}

/// Today's foreground screen time from UsageStats (needs the user's
/// permission in system settings).
Future<int?> syncScreenTime(WidgetRef ref) async {
  final source = ref.read(screenTimeProvider);
  if (source == null) return null;
  try {
    final minutes = await source.minutesToday();
    if (minutes == null) return null;
    await ref.read(dailyLogRepositoryProvider).update(
          isoDate(ref.read(todayProvider)),
          DailyLogsCompanion(screenMinutes: Value(minutes)),
        );
    return minutes;
  } on Object {
    return null;
  }
}

/// Meal reminders from the shift schedule and the next session day.
Future<void> rescheduleReminders(WidgetRef ref) async {
  final service = ref.read(notificationServiceProvider);
  final profile = ref.read(profileProvider).value;
  if (profile == null) return;
  final settings = ref.read(settingsProvider);
  final a = ref.read(currentAssumptionsProvider);
  final today = ref.read(todayProvider);
  final plan = ref.read(sessionPlanProvider);
  final shift = ShiftConfig.fromClock(
    shiftStart: profile.shiftStart,
    shiftEnd: profile.shiftEnd,
    lunchStart: profile.lunchStart,
  );
  final effort = WorkEffort.parse(ref.read(todayLogProvider)?.workEffort);
  try {
    await service.scheduleMeals(
      mealSchedule(
        shift: shift,
        trainingDay: plan.isDue(today),
        workday: effort != WorkEffort.off,
        params: ScheduleParams.fromAssumptions(a),
      ),
      enabled: settings.mealReminders,
    );
    await service.scheduleSession(
      plan.earliestDate,
      'Sesión ${plan.template.code} · ${plan.mode.labelEs}. Antes, revisa tu estado.',
      enabled: settings.sessionReminder,
    );
  } on Object {
    // Exact alarms or notifications not allowed yet: reminders stay off.
  }
}
