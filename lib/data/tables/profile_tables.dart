import 'package:drift/drift.dart';

/// Single-row profile (`id = 1`).
@DataClassName('ProfileRow')
class Profile extends Table {
  IntColumn get id => integer().check(id.equals(1))();
  TextColumn get name => text()();
  IntColumn get birthYear => integer()();
  RealColumn get heightCm => real()();
  TextColumn get sex => text()();
  RealColumn get targetWeightKg => real()();
  TextColumn get shiftStart => text().withDefault(const Constant('07:00'))();
  TextColumn get shiftEnd => text().withDefault(const Constant('17:00'))();
  TextColumn get lunchStart => text().withDefault(const Constant('12:00'))();

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
  RealColumn get heatHours => real().nullable()();
  BoolColumn get ppeFull => boolean().nullable()();
  RealColumn get sweatPreKg => real().nullable()();
  RealColumn get sweatPostKg => real().nullable()();
  RealColumn get fluidsL => real().nullable()();
  RealColumn get urineL => real().nullable()();
  IntColumn get screenMinutes => integer().nullable()();
  BoolColumn get sober => boolean().nullable()();
  IntColumn get sleepSubjective => integer()
      .nullable()
      .check(sleepSubjective.isBetweenValues(1, 5))();

  /// Extension: the user confirmed every meal of the day was logged. Only
  /// these days count toward the adaptive TDEE.
  BoolColumn get intakeComplete =>
      boolean().withDefault(const Constant(false))();

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
