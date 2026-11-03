// Drift column checks reference their own getter by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

/// One block of the user's weekly day template. Nothing is preloaded: the
/// user creates every block (kind, time, weekdays, alarm).
@DataClassName('ScheduleBlockRow')
class ScheduleBlocks extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// A `BlockKind` code from humanos_core.
  TextColumn get kind => text()();

  /// The user's own name; the kind's name when null.
  TextColumn get label => text().nullable()();

  /// `HH:MM`.
  TextColumn get startClock => text()();

  /// Null: until the next block starts.
  IntColumn get durationMin => integer().nullable().check(durationMin.isBiggerThanValue(0))();

  /// Bit 0 Monday … bit 6 Sunday.
  IntColumn get daysMask => integer().check(daysMask.isBetweenValues(1, 127))();
  BoolColumn get alarm => boolean().withDefault(const Constant(false))();
  TextColumn get status =>
      text().withDefault(const Constant('activo')).check(status.isIn(const ['activo', 'pausado', 'archivado']))();
  TextColumn get createdAt => text()();
}

/// A change for one date ("hoy hago horas extra hasta las 20:00"). The
/// template stays as it was.
@DataClassName('ScheduleAdjustmentRow')
class ScheduleAdjustments extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `YYYY-MM-DD`.
  TextColumn get date => text()();
  TextColumn get action => text().check(action.isIn(const ['saltar', 'mover', 'extender', 'agregar']))();
  IntColumn get blockId => integer().nullable().references(ScheduleBlocks, #id)();

  /// `HH:MM`, as the action needs.
  TextColumn get startClock => text().nullable()();
  TextColumn get endClock => text().nullable()();

  /// For an added block.
  TextColumn get kind => text().nullable()();
  TextColumn get label => text().nullable()();
  BoolColumn get alarm => boolean().withDefault(const Constant(false))();
  TextColumn get createdAt => text()();
}
