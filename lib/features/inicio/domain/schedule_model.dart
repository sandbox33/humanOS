import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/user_db.dart';
import '../../../services/notifications.dart';
import '../data/schedule_repository.dart';

/// Home-screen settings (user data; nothing preset).
abstract final class LauncherKey {
  /// Packages always shown on INICIO (comma separated), chosen by the user.
  static const pinned = 'launcher_pinned';
}

final scheduleRepositoryProvider = Provider<ScheduleRepository>(
  (ref) => ScheduleRepository(ref.watch(userDbProvider), ref.watch(clockProvider)),
);

final blockRowsProvider = StreamProvider<List<ScheduleBlockRow>>((ref) => ref.watch(scheduleRepositoryProvider).watchBlocks());

final blockTemplatesProvider = Provider<List<BlockTemplate>>(
  (ref) => templatesOf(ref.watch(blockRowsProvider).value ?? const <ScheduleBlockRow>[]),
);

/// Adjustments from yesterday to tomorrow, by date.
final adjustmentsProvider = StreamProvider<Map<String, List<DayAdjustment>>>((ref) {
  final today = ref.watch(todayProvider);
  return ref
      .watch(scheduleRepositoryProvider)
      .watchAdjustments(isoDate(addDays(today, -1)), isoDate(addDays(today, 1)))
      .map((rows) {
    final out = <String, List<DayAdjustment>>{};
    for (final r in rows) {
      final a = adjustmentOf(r);
      if (a != null) (out[r.date] ??= []).add(a);
    }
    return out;
  });
});

/// The plan of today + [offset] days (−1, 0 or 1).
final dayPlanProvider = Provider.family<List<PlannedBlock>, int>((ref, offset) {
  final day = addDays(ref.watch(todayProvider), offset);
  final templates = ref.watch(blockTemplatesProvider);
  final a = ref.watch(currentAssumptionsProvider);
  return planDay(
    templates: templates,
    weekday: day.weekday,
    adjustments: ref.watch(adjustmentsProvider).value?[isoDate(day)] ?? const [],
    minFlexibleMin: a.integer(A.blockMinFlexibleMin),
    mealMin: a.integer(A.mealBlockMin),
  );
});

/// The wall clock, refreshed every minute while INICIO is on screen.
final minuteTickProvider = StreamProvider<DateTime>((ref) {
  final clock = ref.watch(clockProvider);
  final controller = StreamController<DateTime>();
  controller.add(clock());
  final timer = Timer.periodic(const Duration(minutes: 1), (_) => controller.add(clock()));
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

/// What is happening now and what comes next.
final blockNowProvider = Provider((ref) {
  final now = ref.watch(minuteTickProvider).value ?? ref.watch(clockProvider)();
  return blockAt(
    today: ref.watch(dayPlanProvider(0)),
    yesterday: ref.watch(dayPlanProvider(-1)),
    tomorrow: ref.watch(dayPlanProvider(1)),
    nowMin: now.hour * 60 + now.minute,
  );
});

const _templateAlarmBase = 100000;
const _todayAlarmBase = 200000;
const _addedAlarmBase = 300000;

/// Exact alarms of the blocks marked with an alarm. Template blocks repeat
/// on their weekdays; a block moved or skipped today drops today's ring and
/// a moved or added one rings today at its new time. The app rebuilds this
/// list on every start and every change, so a one-day change never
/// survives its day.
List<AlarmSpec> blockAlarms({
  required List<BlockTemplate> templates,
  required List<PlannedBlock> today,
  required DateTime date,
  required int snoozeMinutes,
}) {
  final todayBit = 1 << (date.weekday - 1);
  final changed = {
    for (final b in today)
      if (b.fromTemplate && b.status != BlockStatus.normal) b.id,
  };
  return [
    for (final t in templates)
      if (t.alarm)
        if ((changed.contains(t.id) ? t.daysMask & ~todayBit : t.daysMask) case final mask when mask != 0)
          AlarmSpec(
            id: _templateAlarmBase + t.id,
            label: t.title,
            minuteOfDay: t.startMin,
            daysMask: mask,
            snoozeMinutes: snoozeMinutes,
          ),
    for (final b in today)
      if (b.alarm && b.active && b.status != BlockStatus.normal && b.startMin < 24 * 60)
        AlarmSpec(
          id: b.fromTemplate ? _todayAlarmBase + b.id : _addedAlarmBase - b.id,
          label: b.title,
          minuteOfDay: b.startMin,
          daysMask: todayBit,
          snoozeMinutes: snoozeMinutes,
        ),
  ];
}
