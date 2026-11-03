import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Channels of the app. Every channel is private on the lock screen (only
/// "HumanOS" shows until the phone is unlocked) and no text carries money
/// amounts or place names.
enum ReminderChannel {
  meals('humanos_comidas', 'Comidas', 'Recordatorios de comidas alrededor de tu trabajo'),
  hydration('humanos_termo', 'Termo', 'Antes de un trabajo con calor y en su pausa'),
  training('humanos_entreno', 'Heavy Duty', 'Día de la próxima sesión'),
  dayClose('humanos_cierre', 'Cierre del día', 'Recordatorio opcional para registrar el día');

  const ReminderChannel(this.id, this.nameEs, this.descriptionEs);
  final String id;
  final String nameEs;
  final String descriptionEs;
}

/// One reminder already checked against the notification policy.
class ScheduledReminder {
  const ScheduledReminder({
    required this.channel,
    required this.at,
    required this.title,
    required this.body,
  });

  final ReminderChannel channel;
  final DateTime at;
  final String title;
  final String body;
}

abstract class NotificationService {
  Future<void> init();

  /// Asks for notification permission; [exactAlarms] also opens the
  /// system screen for exact alarms (reminders work inexactly without it).
  Future<bool> requestPermissions({bool exactAlarms = false});

  /// Replaces every scheduled reminder with [reminders].
  Future<void> scheduleAll(List<ScheduledReminder> reminders);
}

class LocalNotificationService implements NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Ids 100–(100 + [_maxScheduled]) belong to the scheduler.
  static const _firstId = 100;
  static const _maxScheduled = 120;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static AndroidNotificationDetails _details(ReminderChannel c) => AndroidNotificationDetails(
        c.id,
        c.nameEs,
        channelDescription: c.descriptionEs,
        importance: c == ReminderChannel.dayClose ? Importance.defaultImportance : Importance.high,
        priority: c == ReminderChannel.dayClose ? Priority.defaultPriority : Priority.high,
        icon: 'ic_stat_humanos',
        visibility: NotificationVisibility.private,
      );

  @override
  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } on Object {
      // Without the zone name, a zone with the phone's current offset still
      // gives the right wall-clock times for the next days.
      final now = DateTime.now();
      final at = now.millisecondsSinceEpoch;
      for (final location in tz.timeZoneDatabase.locations.values) {
        if (location.timeZone(at).offset == now.timeZoneOffset) {
          tz.setLocalLocation(location);
          break;
        }
      }
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_humanos'),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermissions({bool exactAlarms = false}) async {
    await init();
    final granted = await _android?.requestNotificationsPermission() ?? false;
    if (exactAlarms) await _android?.requestExactAlarmsPermission();
    return granted;
  }

  Future<AndroidScheduleMode> _mode() async =>
      (await _android?.canScheduleExactNotifications() ?? false)
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

  @override
  Future<void> scheduleAll(List<ScheduledReminder> reminders) async {
    await init();
    for (var i = 0; i < _maxScheduled; i++) {
      await _plugin.cancel(id: _firstId + i);
    }
    final now = tz.TZDateTime.now(tz.local);
    final future = [
      for (final r in reminders)
        if (tz.TZDateTime.from(r.at, tz.local).isAfter(now)) r,
    ]..sort((a, b) => a.at.compareTo(b.at));
    final mode = await _mode();
    for (var i = 0; i < future.length && i < _maxScheduled; i++) {
      final r = future[i];
      await _plugin.zonedSchedule(
        id: _firstId + i,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime.from(r.at, tz.local),
        notificationDetails: NotificationDetails(android: _details(r.channel)),
        androidScheduleMode: mode,
      );
    }
  }
}

/// No-op implementation for tests and platforms without notifications.
class SilentNotificationService implements NotificationService {
  final List<ScheduledReminder> scheduled = [];

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
}
