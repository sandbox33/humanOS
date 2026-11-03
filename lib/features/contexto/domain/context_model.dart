import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/settings.dart';
import '../../../data/user_db.dart';
import '../../../services/device_context.dart';
import '../../../services/notifications.dart';
import '../../../services/services.dart';
import '../../trabajo/data/work_repository.dart' show TemplateStatus, parseStamp;
import '../../trabajo/domain/work_model.dart';
import '../data/context_repository.dart';

final contextRepositoryProvider = Provider<ContextRepository>((ref) => ContextRepository(ref.watch(userDbProvider)));

final contextParamsProvider =
    Provider<ContextParams>((ref) => ContextParams.fromAssumptions(ref.watch(currentAssumptionsProvider)));

final zoneRowsProvider = StreamProvider<List<ZoneRow>>((ref) => ref.watch(contextRepositoryProvider).watchZones());

final zonesProvider = Provider<List<ContextZone>>((ref) => [
      for (final r in ref.watch(zoneRowsProvider).value ?? const <ZoneRow>[]) zoneOf(r),
    ]);

final contextEventRowsProvider = StreamProvider<List<ContextEventRow>>(
  (ref) => ref.watch(contextRepositoryProvider).watchEvents(now: ref.watch(todayProvider)),
);

final latestCorrectionProvider =
    StreamProvider<ModeCorrectionRow?>((ref) => ref.watch(contextRepositoryProvider).watchLatestCorrection());

final latestCheckinProvider =
    StreamProvider<StateCheckinRow?>((ref) => ref.watch(contextRepositoryProvider).watchLatestCheckin());

final eventReminderRowsProvider = StreamProvider<List<EventReminderRow>>(
  (ref) => ref.watch(contextRepositoryProvider).watchEventReminders(),
);

final alarmRowsProvider = StreamProvider<List<MorningAlarmRow>>((ref) => ref.watch(contextRepositoryProvider).watchAlarms());

/// The zone the user is in, from the stored transitions.
final currentZoneProvider = Provider<({ContextZone zone, DateTime since})?>((ref) {
  if (!ref.watch(settingsProvider).zonesEnabled) return null;
  return currentZone(
    zones: ref.watch(zonesProvider),
    events: zoneEventsOf(ref.watch(contextEventRowsProvider).value ?? const <ContextEventRow>[]),
    now: ref.watch(clockProvider)(),
    params: ref.watch(contextParamsProvider),
  );
});

/// The user's last state (1–5) while it is recent.
final recentStateProvider = Provider<int?>((ref) {
  final row = ref.watch(latestCheckinProvider).value;
  final at = parseStamp(row?.at);
  if (row == null || at == null) return null;
  final now = ref.watch(clockProvider)();
  final hours = ref.watch(contextParamsProvider).correctionHours;
  return now.difference(at) < Duration(hours: hours) ? row.value : null;
});

ModeCorrection? correctionOf(ModeCorrectionRow? row) {
  final at = parseStamp(row?.at);
  if (row == null || at == null) return null;
  return ModeCorrection(
    mode: ContextMode.parse(row.corrected),
    at: at,
    locationMode: row.locationMode == null ? null : ContextMode.parse(row.locationMode),
  );
}

/// Mode = location + time + state, with the user's correction first.
final modeDecisionProvider = Provider<ModeDecision>((ref) {
  final now = ref.watch(clockProvider)();
  final windows = ref.watch(todayWindowsProvider);
  return inferMode(
    now: now,
    locationMode: ref.watch(currentZoneProvider)?.zone.kind,
    inPlannedWork: windows.any((w) => !now.isBefore(w.start) && now.isBefore(w.end)),
    inQuietHours: inQuietHours(now, PolicyParams.fromAssumptions(ref.watch(currentAssumptionsProvider))),
    state: ref.watch(recentStateProvider),
    correction: correctionOf(ref.watch(latestCorrectionProvider).value),
    params: ref.watch(contextParamsProvider),
  );
});

/// Work template linked to the zone the user is in, if any.
final suggestedTemplateProvider = Provider<WorkTemplateRow?>((ref) {
  final zone = ref.watch(currentZoneProvider);
  if (zone == null) return null;
  final rows = ref.watch(zoneRowsProvider).value ?? const <ZoneRow>[];
  final row = rows.where((r) => r.id == zone.zone.id).firstOrNull;
  final template = templateById(ref.watch(workTemplatesProvider).value ?? const [], row?.templateId);
  return template != null && TemplateStatus.parse(template.status) == TemplateStatus.activo ? template : null;
});

/// Result of the last registration of the zones on the phone.
class ZoneSyncStatus extends Notifier<ZoneSyncResult?> {
  @override
  ZoneSyncResult? build() => null;

  void report(ZoneSyncResult result) => state = result;
}

final zoneSyncStatusProvider = NotifierProvider<ZoneSyncStatus, ZoneSyncResult?>(ZoneSyncStatus.new);

/// Registers the active zones on the phone, or removes every geofence when
/// zones are off or the battery test went over the user's limit.
Future<ZoneSyncResult> syncZones(WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final params = ref.read(contextParamsProvider);
  final on = settings.zonesEnabled && !settings.batteryOverLimit;
  final zones = on ? ref.read(zonesProvider).where((z) => z.active).take(params.maxActiveZones) : const <ContextZone>[];
  final result = await ref.read(deviceContextProvider).registerZones(
        [
          for (final z in zones)
            NativeZone(id: z.id, latitude: z.latitude, longitude: z.longitude, radiusM: z.radiusM, silences: z.kind.silences),
        ],
        responsivenessMs: params.responsivenessMin * 60000,
        staleMs: params.staleHours * 3600000,
      );
  ref.read(zoneSyncStatusProvider.notifier).report(result);
  return result;
}

/// Stores the transitions the phone saw while the app was closed.
Future<int> drainTransitions(WidgetRef ref) async {
  final events = await ref.read(deviceContextProvider).drainEvents();
  final repo = ref.read(contextRepositoryProvider);
  for (final e in events) {
    await repo.addEvent(at: e.at, transition: e.transition, source: 'geocerca', zoneId: e.zoneId);
  }
  return events.length;
}

/// Gives the phone the user's reminders for arriving and leaving.
Future<void> syncEventReminders(WidgetRef ref) async {
  final zones = ref.read(zonesProvider).where((z) => z.active).toList();
  final reminders = <NativeEventReminder>[];
  for (final r in ref.read(eventReminderRowsProvider).value ?? const <EventReminderRow>[]) {
    if (TemplateStatus.parse(r.status) != TemplateStatus.activo) continue;
    final List<int> ids;
    if (r.zoneId != null) {
      if (!zones.any((z) => z.id == r.zoneId)) continue;
      ids = [r.zoneId!];
    } else if (r.zoneKind != null) {
      ids = [
        for (final z in zones)
          if (z.kind.code == r.zoneKind) z.id,
      ];
      // A kind with no zone yet cannot fire.
      if (ids.isEmpty) continue;
    } else {
      ids = const [];
    }
    reminders.add(NativeEventReminder(id: r.id, trigger: r.trigger, zoneIds: ids, message: r.message));
  }
  await ref.read(deviceContextProvider).setEventReminders(reminders);
}

/// Gives the phone the active morning alarms.
Future<void> syncAlarms(WidgetRef ref) async {
  final alarms = <AlarmSpec>[];
  for (final a in ref.read(alarmRowsProvider).value ?? const <MorningAlarmRow>[]) {
    if (TemplateStatus.parse(a.status) != TemplateStatus.activo) continue;
    final int minute;
    try {
      minute = parseClock(a.clock);
    } on FormatException {
      continue;
    }
    alarms.add(AlarmSpec(id: a.id, label: a.label, minuteOfDay: minute, daysMask: a.daysMask, snoozeMinutes: a.snoozeMinutes));
  }
  await ref.read(alarmServiceProvider).setAlarms(alarms);
}

/// The user's one-tap correction: stored, and given to the phone's gate.
Future<void> correctMode(WidgetRef ref, ContextMode mode) async {
  final now = ref.read(clockProvider)();
  final decision = ref.read(modeDecisionProvider);
  await ref.read(contextRepositoryProvider).addCorrection(
        at: now,
        inferred: decision.mode,
        corrected: mode,
        locationMode: ref.read(currentZoneProvider)?.zone.kind,
      );
  await ref.read(deviceContextProvider).setManual(
        silencing: mode.silences,
        until: now.add(Duration(hours: ref.read(contextParamsProvider).correctionHours)),
      );
}

/// Turns zones off (also used when the battery test is over the limit).
Future<void> disableZones(WidgetRef ref) async {
  await ref.read(settingsRepositoryProvider).setBool(SettingKey.zonesEnabled, false);
}
