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
    this.hydrationNudges = true,
    this.sessionReminder = true,
    this.fiberFirst = false,
    this.healthConnectPrompted = false,
  });

  factory AppSettingsState.fromMap(Map<String, String> map) => AppSettingsState(
        accent: AccentColor.parse(map[SettingKey.accent]),
        eventFeedback: map[SettingKey.eventFeedback] != '0',
        crtHeaders: map[SettingKey.crtHeaders] != '0',
        mealReminders: map[SettingKey.mealReminders] != '0',
        hydrationNudges: map[SettingKey.hydrationNudges] != '0',
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
  final bool hydrationNudges;
  final bool sessionReminder;

  /// "Almuerzo antes del turno de tarde": fibre-first sequencing. Off by
  /// default because it lowers intake in a surplus phase.
  final bool fiberFirst;
  final bool healthConnectPrompted;
}

abstract final class SettingKey {
  static const accent = 'accent';
  static const eventFeedback = 'event_feedback';
  static const crtHeaders = 'crt_headers';
  static const mealReminders = 'meal_reminders';
  static const hydrationNudges = 'hydration_nudges';
  static const sessionReminder = 'session_reminder';
  static const fiberFirst = 'fiber_first';
  static const healthConnectPrompted = 'health_connect_prompted';
  static const weeklyTargetKcal = 'weekly_target_kcal';
  static const weeklyTargetReviewed = 'weekly_target_reviewed';
  static const usageStatsAsked = 'usage_stats_asked';
  static const bleDeviceId = 'ble_device_id';
  static const healthLastSync = 'health_last_sync';

  /// Value shown in the first weigh-in dialog (seeded, editable there).
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
