// Drift column checks reference their own getter by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

/// Zones created by the user for the geofences. Coordinates stay in this
/// encrypted database; there is no position history, only transitions.
@DataClassName('ZoneRow')
class Zones extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Neutral name chosen by the user.
  TextColumn get name => text()();
  TextColumn get kind => text().check(kind.isIn(const ['chamba', 'entreno', 'descanso', 'otro']))();

  /// The user's own name for an "otro" kind.
  TextColumn get kindLabel => text().nullable()();
  RealColumn get latitude => real().check(latitude.isBetweenValues(-90, 90))();
  RealColumn get longitude => real().check(longitude.isBetweenValues(-180, 180))();
  IntColumn get radiusM => integer().check(radiusM.isBiggerOrEqualValue(1))();
  TextColumn get status => text().withDefault(const Constant('activo')).check(status.isIn(const ['activo', 'pausado', 'archivado']))();

  /// Work template suggested while inside the zone (optional).
  IntColumn get templateId => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text()();
}

/// ENTER/EXIT transitions with their timestamp, from a geofence or from the
/// manual "Llegué" / "Voy a salir" buttons (with optional notes).
@DataClassName('ContextEventRow')
class ContextEvents extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Local wall-clock `YYYY-MM-DDTHH:MM:SS`.
  TextColumn get at => text()();
  IntColumn get zoneId => integer().nullable()();
  TextColumn get transition => text().check(transition.isIn(const ['entrar', 'salir']))();
  TextColumn get source => text().check(source.isIn(const ['geocerca', 'manual']))();
  TextColumn get plan => text().nullable()();
  TextColumn get company => text().nullable()();
  IntColumn get feeling => integer().nullable().check(feeling.isBetweenValues(1, 5))();
}

/// One-tap corrections of the inferred mode (kept to review the rules).
@DataClassName('ModeCorrectionRow')
class ModeCorrections extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get at => text()();
  TextColumn get inferred => text()();
  TextColumn get corrected => text()();

  /// What the location said at that moment (null without a zone).
  TextColumn get locationMode => text().nullable()();
}

/// The user's state (energy and mood, 1–5) entered in one tap.
@DataClassName('StateCheckinRow')
class StateCheckins extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get at => text()();
  IntColumn get value => integer().check(value.isBetweenValues(1, 5))();
}

/// Reminders the user ties to arriving at or leaving a zone (or any place
/// through the manual buttons).
@DataClassName('EventReminderRow')
class EventReminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get message => text()();
  TextColumn get trigger => text().check(trigger.isIn(const ['llegar', 'salir']))();

  /// Limit to one kind of zone, or to one zone; both null = any place.
  TextColumn get zoneKind => text().nullable().check(zoneKind.isIn(const ['chamba', 'entreno', 'descanso', 'otro']))();
  IntColumn get zoneId => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('activo')).check(status.isIn(const ['activo', 'pausado', 'archivado']))();
  TextColumn get createdAt => text()();
}

/// Morning alarms, rung by the phone as exact alarm-clock alarms.
@DataClassName('MorningAlarmRow')
class MorningAlarms extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text()();

  /// `HH:MM`.
  TextColumn get clock => text()();

  /// Weekdays: bit 0 Monday … bit 6 Sunday; at least one.
  IntColumn get daysMask => integer().check(daysMask.isBetweenValues(1, 127))();
  IntColumn get snoozeMinutes => integer().check(snoozeMinutes.isBetweenValues(1, 60))();
  TextColumn get status => text().withDefault(const Constant('activo')).check(status.isIn(const ['activo', 'pausado', 'archivado']))();
  TextColumn get createdAt => text()();
}
