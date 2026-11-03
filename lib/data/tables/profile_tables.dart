// Drift column checks reference their own getter by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

/// Single-row profile (`id = 1`), entered by the user. Work hours live in
/// the user's work templates, not here.
@DataClassName('ProfileRow')
class Profile extends Table {
  IntColumn get id => integer().check(id.equals(1))();
  TextColumn get name => text()();
  IntColumn get birthYear => integer()();
  RealColumn get heightCm => real()();
  TextColumn get sex => text()();
  RealColumn get targetWeightKg => real()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Editable model constants (seeded from `assumptionCatalog`).
@DataClassName('AssumptionRow')
class AssumptionRows extends Table {
  @override
  String get tableName => 'assumptions';

  TextColumn get key => text()();
  RealColumn get value => real()();
  TextColumn get titleEs => text()();
  TextColumn get explainEs => text()();
  TextColumn get source => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DataClassName('BodyMetricRow')
class BodyMetrics extends Table {
  TextColumn get date => text()();
  RealColumn get weightKg => real().nullable()();
  RealColumn get rhrBpm => real().nullable()();
  RealColumn get gripKg => real().nullable()();
  RealColumn get waistCm => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

@DataClassName('DailyLogRow')
class DailyLogs extends Table {
  TextColumn get date => text()();
  TextColumn get workEffort => text()
      .nullable()
      .check(workEffort.isIn(const ['OFF', 'LOW', 'MEDIUM', 'HIGH']))();
  /// Minutes of heat exposure declared for the day.
  IntColumn get heatMinutes => integer().nullable().check(heatMinutes.isBiggerOrEqualValue(0))();
  BoolColumn get ppeFull => boolean().nullable()();
  IntColumn get screenMinutes => integer().nullable()();
  BoolColumn get sober => boolean().nullable()();
  IntColumn get sleepSubjective => integer()
      .nullable()
      .check(sleepSubjective.isBetweenValues(1, 5))();

  /// Extension: the user confirmed every meal of the day was logged. Only
  /// these days count toward the adaptive TDEE.
  BoolColumn get intakeComplete =>
      boolean().withDefault(const Constant(false))();

  // Schema v2: 1-tap after work and the morning check-in.
  TextColumn get sweatFeel =>
      text().nullable().check(sweatFeel.isIn(const ['poco', 'normal', 'mucho']))();
  IntColumn get effortFeel => integer().nullable().check(effortFeel.isBetweenValues(1, 5))();

  /// Morning check-in 1–5 (how the user woke up).
  IntColumn get mood => integer().nullable().check(mood.isBetweenValues(1, 5))();

  /// Thermos reminders acknowledged (before work, in the break).
  BoolColumn get thermoPre => boolean().nullable()();
  BoolColumn get thermoBreak => boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

/// Key/value app settings (accent colour, toggles, onboarding state).
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
