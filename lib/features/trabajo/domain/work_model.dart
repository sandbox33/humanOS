import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/user_db.dart';
import '../../estado/domain/targets.dart';
import '../data/work_repository.dart';

final workRepositoryProvider =
    Provider<WorkRepository>((ref) => WorkRepository(ref.watch(userDbProvider)));

final workTemplatesProvider = StreamProvider<List<WorkTemplateRow>>(
  (ref) => ref.watch(workRepositoryProvider).watchTemplates(),
);

/// Templates offered for quick logging (paused and archived are hidden).
final activeTemplatesProvider = Provider<List<WorkTemplateRow>>((ref) => [
      for (final t in ref.watch(workTemplatesProvider).value ?? const <WorkTemplateRow>[])
        if (TemplateStatus.parse(t.status) == TemplateStatus.activo) t,
    ]);

/// Entries of roughly the last two months (enough for the month total).
final workEntryRowsProvider = StreamProvider<List<WorkEntryRow>>((ref) {
  final from = isoDate(addDays(ref.watch(todayProvider), -62));
  return ref.watch(workRepositoryProvider).watchEntriesSince(from);
});

final workEntriesProvider = Provider<List<WorkEntry>>((ref) => [
      for (final r in ref.watch(workEntryRowsProvider).value ?? const <WorkEntryRow>[])
        entryFromRow(r),
    ]);

final workSummaryProvider = Provider((ref) {
  final settings = ref.watch(settingsProvider);
  return workSummary(
    ref.watch(workEntriesProvider),
    today: ref.watch(todayProvider),
    dailyOvertimeMin: settings.overtimeDayMin,
    weeklyOvertimeMin: settings.overtimeWeekMin,
  );
});

/// The entry started and not finished, if any.
final inProgressEntryProvider = Provider<({WorkEntry entry, WorkEntryRow row})?>((ref) {
  for (final r in ref.watch(workEntryRowsProvider).value ?? const <WorkEntryRow>[]) {
    if (r.startTs != null && r.endTs == null) return (entry: entryFromRow(r), row: r);
  }
  return null;
});

WorkTemplateRow? templateById(List<WorkTemplateRow> templates, int? id) {
  if (id == null) return null;
  for (final t in templates) {
    if (t.id == id) return t;
  }
  return null;
}

/// Silence windows touching [day]: planned active templates plus the entry
/// in progress.
List<WorkWindow> silenceWindowsFor(DateTime day, Ref ref) {
  final templates = ref.watch(workTemplatesProvider).value ?? const <WorkTemplateRow>[];
  final active = [
    for (final t in templates)
      if (TemplateStatus.parse(t.status) == TemplateStatus.activo) scheduleOf(t),
  ];
  final windows = plannedWindows(day, active);
  final running = ref.watch(inProgressEntryProvider);
  if (running != null) {
    final template = templateById(templates, running.row.templateId);
    final w = inProgressWindow(
      running.entry,
      openHours: ref.watch(currentAssumptionsProvider).integer(A.workOpenWindowH),
      schedule: template == null ? null : scheduleOf(template),
    );
    if (w != null) windows.add(w);
  }
  return windows;
}

final todayWindowsProvider = Provider<List<WorkWindow>>(
  (ref) => silenceWindowsFor(ref.watch(todayProvider), ref),
);

/// Planned minutes of work today (from templates), when no entry exists.
final plannedMinutesTodayProvider = Provider<int?>((ref) {
  final today = ref.watch(todayProvider);
  var total = 0;
  var any = false;
  for (final t in ref.watch(activeTemplatesProvider)) {
    final s = scheduleOf(t);
    if (!s.plannedOn(today)) continue;
    any = true;
    total += s.plannedMinutes(today) ?? 0;
  }
  return any ? total : null;
});

/// Minutes of work logged today (entries), or null when nothing is logged.
final workedMinutesTodayProvider = Provider<int?>((ref) {
  final day = ref.watch(workSummaryProvider).day;
  return day.entries == 0 ? null : day.minutes;
});

/// Sweat feel of the recent days (`daily_logs.sweat_feel`).
final sweatFeelHistoryProvider = Provider<List<SweatFeelEntry>>((ref) => [
      for (final l in ref.watch(dailyLogsProvider).value ?? const <DailyLogRow>[])
        if (SweatFeel.parse(l.sweatFeel) case final feel?)
          SweatFeelEntry(date: parseIsoDate(l.date), feel: feel),
    ]);

/// Minutes of heat for today's plan: what the user declared, otherwise the
/// heat of the planned windows.
final heatMinutesTodayProvider = Provider<int>((ref) {
  final declared = ref.watch(todayLogProvider)?.heatMinutes;
  if (declared != null) return declared;
  return plannedHeatMinutes(ref.watch(todayWindowsProvider));
});

final hydrationPlanProvider = Provider<HydrationPlan>((ref) => hydrationPlan(
      heatMinutes: ref.watch(heatMinutesTodayProvider),
      feelHistory: ref.watch(sweatFeelHistoryProvider),
      today: ref.watch(todayProvider),
      params: HydrationParams.fromAssumptions(ref.watch(currentAssumptionsProvider)),
    ));

/// Thermos reminders acknowledged today (0–2), for the H2O habit.
final thermoAcksTodayProvider = Provider<int>((ref) {
  final log = ref.watch(todayLogProvider);
  return (log?.thermoPre == true ? 1 : 0) + (log?.thermoBreak == true ? 1 : 0);
});

/// The first window that starts on [day], as the frame of the meal
/// schedule (start, end and break or midpoint). Null without planned work.
ShiftConfig? mealFrameFor(DateTime day, List<WorkWindow> windows) {
  final start = DateTime(day.year, day.month, day.day);
  final own = [
    for (final w in windows)
      if (!w.start.isBefore(start) && w.start.isBefore(start.add(const Duration(days: 1)))) w,
  ]..sort((a, b) => a.start.compareTo(b.start));
  if (own.isEmpty) return null;
  final w = own.first;
  int minute(DateTime t) => t.hour * 60 + t.minute;
  final lunch = w.breakStart ?? w.start.add(w.end.difference(w.start) ~/ 2);
  return ShiftConfig(
    shiftStartMin: minute(w.start),
    shiftEndMin: minute(w.end),
    lunchStartMin: minute(lunch),
    lunchMinutes: switch ((w.breakStart, w.breakEnd)) {
      (final from?, final to?) => to.difference(from).inMinutes,
      _ => null,
    },
  );
}
