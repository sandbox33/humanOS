import 'package:drift/drift.dart';

@DataClassName('SessionRow')
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  TextColumn get template =>
      text().check(template.isIn(const ['A', 'B', 'BASELINE']))();
  TextColumn get readiness => text()
      .nullable()
      .check(readiness.isIn(const ['VERDE', 'AMARILLO', 'ROJO']))();
  BoolColumn get readinessOverridden =>
      boolean().withDefault(const Constant(false))();
  RealColumn get avgHr => real().nullable()();
  RealColumn get maxHr => real().nullable()();
  TextColumn get notes => text().nullable()();

  /// Extension: normal / deload / retest (the deload week must be known).
  TextColumn get mode => text()
      .withDefault(const Constant('normal'))
      .check(mode.isIn(const ['normal', 'deload', 'retest']))();
}

@DataClassName('SetRow')
class Sets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId =>
      integer().references(Sessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId => integer()();
  RealColumn get loadKg => real()();
  IntColumn get reps => integer()();
  IntColumn get validReps => integer()();
  RealColumn get tutS => real().nullable()();
  BoolColumn get reachedFailure => boolean()();
  IntColumn get restPauseReps => integer().withDefault(const Constant(0))();
  BoolColumn get isWarmup => boolean().withDefault(const Constant(false))();
  IntColumn get poseReps => integer().nullable()();

  /// Tap times in ms since the set started, as a JSON number list.
  TextColumn get repTimestamps => text().nullable()();
}

@DataClassName('PersonalRecordRow')
class PersonalRecords extends Table {
  IntColumn get exerciseId => integer()();
  RealColumn get loadKg => real()();
  IntColumn get reps => integer()();
  RealColumn get e1rm => real()();
  TextColumn get date => text()();

  @override
  Set<Column<Object>> get primaryKey => {exerciseId};
}

@DataClassName('ReadinessRow')
class Readiness extends Table {
  TextColumn get date => text()();
  RealColumn get hrvLnRmssd => real().nullable()();
  RealColumn get rhr => real().nullable()();
  RealColumn get sleepMin => real().nullable()();
  TextColumn get sleepSource => text().nullable()();
  TextColumn get band => text()
      .nullable()
      .check(band.isIn(const ['VERDE', 'AMARILLO', 'ROJO']))();
  TextColumn get reasons => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

@DataClassName('TelemetrySampleRow')
class TelemetrySamples extends Table {
  TextColumn get type => text()();
  TextColumn get start => text()();
  TextColumn get end => text().nullable()();
  RealColumn get value => real().nullable()();
  TextColumn get source => text()();

  @override
  Set<Column<Object>> get primaryKey => {type, start, source};
}
