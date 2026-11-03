import 'user_db.dart';

/// Accent colours allowed by the visual identity.
enum AccentColor {
  phosphor('green', 'VERDE FÓSFORO'),
  safetyOrange('orange', 'NARANJA SEGURIDAD');

  const AccentColor(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static AccentColor parse(String? code) => AccentColor.values
      .firstWhere((a) => a.code == code, orElse: () => AccentColor.phosphor);
}

/// Typed view of `app_settings`.
class AppSettingsState {
  const AppSettingsState({
    this.accent = AccentColor.phosphor,
    this.eventFeedback = true,
    this.crtHeaders = true,
    this.mealReminders = true,
    this.hydrationReminders = true,
    this.dayCloseTime,
    this.overtimeDayMin,
    this.overtimeWeekMin,
    this.sessionReminder = true,
    this.fiberFirst = false,
    this.healthConnectPrompted = false,
  });

  factory AppSettingsState.fromMap(Map<String, String> map) => AppSettingsState(
        accent: AccentColor.parse(map[SettingKey.accent]),
        eventFeedback: map[SettingKey.eventFeedback] != '0',
        crtHeaders: map[SettingKey.crtHeaders] != '0',
        mealReminders: map[SettingKey.mealReminders] != '0',
        hydrationReminders: map[SettingKey.hydrationReminders] != '0',
        dayCloseTime: map[SettingKey.dayCloseTime],
        overtimeDayMin: int.tryParse(map[SettingKey.overtimeDayMin] ?? ''),
        overtimeWeekMin: int.tryParse(map[SettingKey.overtimeWeekMin] ?? ''),
        sessionReminder: map[SettingKey.sessionReminder] != '0',
        fiberFirst: map[SettingKey.fiberFirst] == '1',
        healthConnectPrompted: map[SettingKey.healthConnectPrompted] == '1',
      );

  final AccentColor accent;

  /// ≤ 600 ms flash + haptic on a real event (PR, streak, attribute up).
  final bool eventFeedback;

  /// Static scanlines on headers; turned off automatically if frames lag.
  final bool crtHeaders;
  final bool mealReminders;
  /// "Llena el termo" before planned work with heat and at its break.
  final bool hydrationReminders;

  /// Optional day-close reminder (`HH:MM`), off when null.
  final String? dayCloseTime;

  /// Optional overtime thresholds in minutes (no default rule).
  final int? overtimeDayMin;
  final int? overtimeWeekMin;
  final bool sessionReminder;

  /// Fibre-first sequencing at lunch. Off by
  /// default because it lowers intake in a surplus phase.
  final bool fiberFirst;
  final bool healthConnectPrompted;
}

abstract final class SettingKey {
  static const accent = 'accent';
  static const eventFeedback = 'event_feedback';
  static const crtHeaders = 'crt_headers';
  static const mealReminders = 'meal_reminders';
  static const hydrationReminders = 'hydration_reminders';
  static const dayCloseTime = 'day_close_time';
  static const overtimeDayMin = 'overtime_day_min';
  static const overtimeWeekMin = 'overtime_week_min';
  static const sessionReminder = 'session_reminder';
  static const fiberFirst = 'fiber_first';
  static const healthConnectPrompted = 'health_connect_prompted';
  static const weeklyTargetKcal = 'weekly_target_kcal';
  static const weeklyTargetReviewed = 'weekly_target_reviewed';
  static const usageStatsAsked = 'usage_stats_asked';
  static const bleDeviceId = 'ble_device_id';
  static const healthLastSync = 'health_last_sync';

  /// Value shown in the first weigh-in dialog when there is no weight yet.
  static const weightPrefill = 'weight_prefill_kg';
  static const healthGranted = 'health_granted';
  static const notificationsAsked = 'notifications_asked';
}

class SettingsRepository {
  SettingsRepository(this._db);
  final UserDb _db;

  Stream<Map<String, String>> watchAll() =>
      _db.select(_db.appSettings).watch().map(
            (rows) => {for (final r in rows) r.key: r.value},
          );

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));

  Future<void> setBool(String key, bool value) => set(key, value ? '1' : '0');

  Future<void> remove(String key) =>
      (_db.delete(_db.appSettings)..where((t) => t.key.equals(key))).go();
}
