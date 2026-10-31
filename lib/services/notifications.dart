import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:humanos_core/humanos_core.dart' show ContextRule;

/// Channels of the app. Every channel is private on the lock screen (only
/// "HumanOS" shows until the phone is unlocked) and no text carries money
/// amounts or place names. The phone creates them (`Notices.kt`).
enum ReminderChannel {
  meals('humanos_comidas'),
  hydration('humanos_termo'),
  training('humanos_entreno'),
  dayClose('humanos_cierre');

  const ReminderChannel(this.id);
  final String id;
}

/// One reminder already checked against the notification policy. [rule]
/// says what the phone does if it falls due in chamba or entreno.
class ScheduledReminder {
  const ScheduledReminder({
    required this.channel,
    required this.at,
    required this.title,
    required this.body,
    this.rule = ContextRule.allow,
  });

  final ReminderChannel channel;
  final DateTime at;
  final String title;
  final String body;
  final ContextRule rule;
}

abstract class NotificationService {
  Future<void> init();

  /// Asks for notification permission; [exactAlarms] also opens the
  /// system screen for exact alarms (reminders work inexactly without it).
  Future<bool> requestPermissions({bool exactAlarms = false});

  /// Replaces every scheduled reminder with [reminders].
  Future<void> scheduleAll(List<ScheduledReminder> reminders);
}

/// A morning alarm as the phone schedules it.
class AlarmSpec {
  const AlarmSpec({
    required this.id,
    required this.label,
    required this.minuteOfDay,
    required this.daysMask,
    required this.snoozeMinutes,
  });

  final int id;
  final String label;
  final int minuteOfDay;
  final int daysMask;
  final int snoozeMinutes;

  Map<String, Object> toMap() => {
    'id': id,
    'label': label,
    'minuteOfDay': minuteOfDay,
    'daysMask': daysMask,
    'snoozeMin': snoozeMinutes,
  };
}

abstract class AlarmService {
  /// Replaces every alarm on the phone with [alarms].
  Future<void> setAlarms(List<AlarmSpec> alarms);

  /// Rings the alarm screen now, to check sound and volume.
  Future<void> ringNow(String label);
}

/// What the phone holds right now (DIAGNÓSTICO).
class SchedulerState {
  const SchedulerState({required this.pending, required this.deferred, required this.next, required this.exact});

  final int pending;
  final int deferred;
  final DateTime? next;
  final bool exact;
}

/// Reminders and alarms scheduled by the phone itself (`Scheduler.kt`,
/// `Alarms.kt`), so the location context can hold them back even with the
/// app closed. flutter_local_notifications only asks for permissions and
/// clears what older versions scheduled through it.
class NativeNotificationService implements NotificationService, AlarmService {
  static const _channel = MethodChannel('com.altair.humanos/scheduler');
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_humanos'),
      ),
    );
    // Schedules left by earlier versions through the plugin. Only pending
    // ones: an alarm ringing now is not touched.
    for (final pending in await _plugin.pendingNotificationRequests()) {
      await _plugin.cancel(id: pending.id);
    }
    _ready = true;
  }

  @override
  Future<bool> requestPermissions({bool exactAlarms = false}) async {
    await init();
    final granted = await _android?.requestNotificationsPermission() ?? false;
    if (exactAlarms) await _channel.invokeMethod<bool>('openExactAlarmSettings');
    return granted;
  }

  @override
  Future<void> scheduleAll(List<ScheduledReminder> reminders) async {
    final future = [
      for (final r in reminders)
        if (r.at.isAfter(DateTime.now())) r,
    ]..sort((a, b) => a.at.compareTo(b.at));
    await _channel.invokeMethod<void>('setReminders', {
      'reminders': [
        for (var i = 0; i < future.length; i++)
          {
            'id': i,
            'atMs': future[i].at.millisecondsSinceEpoch,
            'channel': future[i].channel.id,
            'title': future[i].title,
            'body': future[i].body,
            'rule': future[i].rule.code,
          },
      ],
    });
  }

  @override
  Future<void> setAlarms(List<AlarmSpec> alarms) =>
      _channel.invokeMethod<void>('setAlarms', {'alarms': [for (final a in alarms) a.toMap()]});

  @override
  Future<void> ringNow(String label) => _channel.invokeMethod<void>('ringNow', {'label': label});

  Future<SchedulerState?> state() async {
    final m = await _channel.invokeMapMethod<String, Object?>('state');
    if (m == null) return null;
    final next = m['nextMs'] as int?;
    return SchedulerState(
      pending: m['pending'] as int? ?? 0,
      deferred: m['deferred'] as int? ?? 0,
      next: next == null ? null : DateTime.fromMillisecondsSinceEpoch(next),
      exact: m['exact'] == true,
    );
  }
}

/// No-op implementation for tests and platforms without notifications;
/// keeps what was scheduled so tests can read it.
class SilentNotificationService implements NotificationService, AlarmService {
  final List<ScheduledReminder> scheduled = [];
  final List<AlarmSpec> alarms = [];
  final List<String> rung = [];

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermissions({bool exactAlarms = false}) async => false;
  @override
  Future<void> scheduleAll(List<ScheduledReminder> reminders) async {
    scheduled
      ..clear()
      ..addAll(reminders);
  }

  @override
  Future<void> setAlarms(List<AlarmSpec> alarms) async {
    this.alarms
      ..clear()
      ..addAll(alarms);
  }

  @override
  Future<void> ringNow(String label) async => rung.add(label);
}
