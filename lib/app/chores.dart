import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../data/settings.dart';
import '../data/user_db.dart';
import '../features/estado/domain/readiness_today.dart';
import '../features/estado/domain/targets.dart';
import '../features/heavy_duty/domain/training_plan.dart';
import '../features/trabajo/data/work_repository.dart';
import '../features/trabajo/domain/work_model.dart';
import '../services/notifications.dart';
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

/// Days ahead covered by the reminder schedule.
const reminderDays = 7;

/// Rebuilds every reminder of the next days. All of them pass the
/// notification policy: nothing inside a work window (planned in a
/// template or in progress) except its break, and meal or day-close
/// reminders never in quiet hours.
Future<void> rescheduleReminders(WidgetRef ref) async {
  final service = ref.read(notificationServiceProvider);
  final settings = ref.read(settingsProvider);
  final a = ref.read(currentAssumptionsProvider);
  final today = ref.read(todayProvider);
  final plan = ref.read(sessionPlanProvider);
  final policy = PolicyParams.fromAssumptions(a);
  final hydration = HydrationParams.fromAssumptions(a);
  final schedules = [for (final t in ref.read(activeTemplatesProvider)) scheduleOf(t)];
  final feel = ref.read(sweatFeelHistoryProvider);
  final running = ref.read(inProgressEntryProvider);
  final templates = ref.read(workTemplatesProvider).value ?? const <WorkTemplateRow>[];
  final runningWindow = running == null
      ? null
      : inProgressWindow(
          running.entry,
          openHours: a.integer(A.workOpenWindowH),
          schedule: switch (templateById(templates, running.row.templateId)) {
            final t? => scheduleOf(t),
            null => null,
          },
        );

  final reminders = <ScheduledReminder>[];
  bool allowed(NotificationKind kind, DateTime at, List<WorkWindow> windows) =>
      evaluateNotification(kind: kind, at: at, windows: windows, params: policy).allowed;

  for (var offset = 0; offset < reminderDays; offset++) {
    final d = addDays(today, offset);
    final day = DateTime(d.year, d.month, d.day);
    final windows = [...plannedWindows(day, schedules), ?runningWindow];

    if (settings.mealReminders) {
      final frame = mealFrameFor(day, windows);
      if (frame != null) {
        for (final slot in mealSchedule(
          shift: frame,
          trainingDay: offset == 0 ? plan.isDue(d) : dateOnly(plan.earliestDate) == dateOnly(d),
          workday: true,
          params: ScheduleParams.fromAssumptions(a),
        )) {
          final at = day.add(Duration(minutes: slot.minuteOfDay));
          if (!allowed(NotificationKind.meal, at, windows)) continue;
          reminders.add(ScheduledReminder(
            channel: ReminderChannel.meals,
            at: at,
            title: slot.block.labelEs,
            body: '${slot.clock} · ${slot.contextEs}',
          ));
        }
      }
    }

    if (settings.hydrationReminders) {
      final heat = plannedHeatMinutes(windows);
      if (heat > 0) {
        final thermos = hydrationPlan(heatMinutes: heat, feelHistory: feel, today: d, params: hydration);
        for (final r in hydrationReminders(windows: windows, plan: thermos, params: hydration)) {
          if (!allowed(NotificationKind.hydration, r.at, windows)) continue;
          reminders.add(ScheduledReminder(
            channel: ReminderChannel.hydration,
            at: r.at,
            title: r.titleEs,
            body: r.bodyEs,
          ));
        }
      }
    }

    if (settings.sessionReminder && dateOnly(plan.earliestDate) == dateOnly(d) && windows.isNotEmpty) {
      final end = windows.map((w) => w.end).reduce((x, y) => x.isAfter(y) ? x : y);
      if (allowed(NotificationKind.session, end, windows)) {
        reminders.add(ScheduledReminder(
          channel: ReminderChannel.training,
          at: end,
          title: 'HEAVY DUTY',
          body: 'Sesión ${plan.template.code} · ${plan.mode.labelEs}. Antes, revisa tu estado.',
        ));
      }
    }

    final close = settings.dayCloseTime;
    if (close != null) {
      try {
        final at = day.add(Duration(minutes: parseClock(close)));
        if (allowed(NotificationKind.dayClose, at, windows)) {
          reminders.add(ScheduledReminder(
            channel: ReminderChannel.dayClose,
            at: at,
            title: 'CIERRE DEL DÍA',
            body: '¿Registraste tu trabajo y tus comidas de hoy?',
          ));
        }
      } on FormatException {
        // A malformed time keeps the day-close reminder off.
      }
    }
  }
  try {
    await service.scheduleAll(reminders);
  } on Object {
    // Exact alarms or notifications not allowed yet: reminders stay off.
  }
}
