import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:humanos_core/humanos_core.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local reminders: meals from the shift schedule, hydration nudges during
/// declared heat hours, and the next Heavy Duty day.
abstract class NotificationService {
  Future<void> init();
  /// Asks for notification permission; [exactAlarms] also opens the
  /// system screen for exact alarms (reminders work inexactly without it).
  Future<bool> requestPermissions({bool exactAlarms = false});
  Future<void> scheduleMeals(List<MealSlot> slots, {required bool enabled});
  Future<void> scheduleHydration({
    required DateTime from,
    required DateTime until,
    required int everyMinutes,
    required String body,
    required bool enabled,
  });
  /// Reminder on the next session day at [minuteOfDay] (the end of the
  /// shift).
  Future<void> scheduleSession(DateTime? day, String body,
      {required int minuteOfDay, required bool enabled});
}

class LocalNotificationService implements NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _mealBase = 100;
  static const _hydrationBase = 200;
  static const _hydrationMax = 48;
  static const _sessionId = 300;

  static const _meals = AndroidNotificationDetails(
    'humanos_comidas',
    'Comidas',
    channelDescription: 'Recordatorios de las comidas del turno',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_stat_humanos',
  );
  static const _water = AndroidNotificationDetails(
    'humanos_hidratacion',
    'Hidratación',
    channelDescription: 'Avisos de agua durante las horas de calor',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_stat_humanos',
  );
  static const _training = AndroidNotificationDetails(
    'humanos_entreno',
    'Heavy Duty',
    channelDescription: 'Día de la próxima sesión',
    importance: Importance.defaultImportance,
    icon: 'ic_stat_humanos',
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } on Object {
      tz.setLocalLocation(tz.getLocation('America/Guayaquil'));
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
  Future<void> scheduleMeals(List<MealSlot> slots, {required bool enabled}) async {
    await init();
    for (var i = 0; i < MealBlock.values.length; i++) {
      await _plugin.cancel(id: _mealBase + i);
    }
    if (!enabled) return;
    final mode = await _mode();
    final now = tz.TZDateTime.now(tz.local);
    for (final slot in slots) {
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day,
          slot.minuteOfDay ~/ 60, slot.minuteOfDay % 60);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id: _mealBase + slot.block.index,
        title: slot.block.labelEs,
        body: '${slot.clock} · ${slot.contextEs}',
        scheduledDate: at,
        notificationDetails: const NotificationDetails(android: _meals),
        androidScheduleMode: mode,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  @override
  Future<void> scheduleHydration({
    required DateTime from,
    required DateTime until,
    required int everyMinutes,
    required String body,
    required bool enabled,
  }) async {
    await init();
    for (var i = 0; i < _hydrationMax; i++) {
      await _plugin.cancel(id: _hydrationBase + i);
    }
    if (!enabled || everyMinutes <= 0) return;
    final mode = await _mode();
    var at = from.add(Duration(minutes: everyMinutes));
    for (var i = 0; i < _hydrationMax && !at.isAfter(until); i++) {
      await _plugin.zonedSchedule(
        id: _hydrationBase + i,
        title: 'AGUA',
        body: body,
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: const NotificationDetails(android: _water),
        androidScheduleMode: mode,
      );
      at = at.add(Duration(minutes: everyMinutes));
    }
  }

  @override
  Future<void> scheduleSession(DateTime? day, String body,
      {required int minuteOfDay, required bool enabled}) async {
    await init();
    await _plugin.cancel(id: _sessionId);
    if (!enabled || day == null) return;
    final at = tz.TZDateTime(
        tz.local, day.year, day.month, day.day, minuteOfDay ~/ 60, minuteOfDay % 60);
    if (!at.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id: _sessionId,
      title: 'HEAVY DUTY',
      body: body,
      scheduledDate: at,
      notificationDetails: const NotificationDetails(android: _training),
      androidScheduleMode: await _mode(),
    );
  }
}

/// No-op implementation for tests and platforms without notifications.
class SilentNotificationService implements NotificationService {
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermissions({bool exactAlarms = false}) async => false;
  @override
  Future<void> scheduleMeals(List<MealSlot> slots, {required bool enabled}) async {}
  @override
  Future<void> scheduleHydration({
    required DateTime from,
    required DateTime until,
    required int everyMinutes,
    required String body,
    required bool enabled,
  }) async {}
  @override
  Future<void> scheduleSession(DateTime? day, String body,
      {required int minuteOfDay, required bool enabled}) async {}
}
