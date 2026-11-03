// Drift column checks reference their own getter by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

/// One piece of work. Money in integer cents, time in integer minutes.
/// Timestamps are local wall-clock `YYYY-MM-DDTHH:MM:SS`; the end may fall
/// on the next day (work across midnight).
@DataClassName('WorkEntryRow')
class WorkEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Day the work started (`YYYY-MM-DD`).
  TextColumn get date => text()();
  TextColumn get label => text()();
  TextColumn get kind => text().check(kind.isIn(const ['estable', 'eventual']))();
  TextColumn get startTs => text().nullable()();
  TextColumn get endTs => text().nullable()();
  IntColumn get minutes => integer().check(minutes.isBiggerOrEqualValue(0))();
  IntColumn get rateCentsPerHour =>
      integer().nullable().check(rateCentsPerHour.isBiggerOrEqualValue(0))();

  /// Null when unknown (never assumed to be zero).
  IntColumn get earnedCents => integer().nullable().check(earnedCents.isBiggerOrEqualValue(0))();
  TextColumn get note => text().nullable()();
  TextColumn get createdAt => text()();
  IntColumn get templateId => integer().nullable()();
}

/// Quick-log shortcuts created by the user (label, rate, usual times and
/// planned days). Nothing is preloaded.
@DataClassName('WorkTemplateRow')
class WorkTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text()();
  TextColumn get kind => text().check(kind.isIn(const ['estable', 'eventual']))();
  IntColumn get rateCentsPerHour =>
      integer().nullable().check(rateCentsPerHour.isBiggerOrEqualValue(0))();

  /// `HH:MM`, all optional.
  TextColumn get startClock => text().nullable()();
  TextColumn get endClock => text().nullable()();
  TextColumn get breakStart => text().nullable()();
  IntColumn get breakMinutes => integer().nullable().check(breakMinutes.isBiggerOrEqualValue(0))();

  /// Planned weekdays: bit 0 Monday … bit 6 Sunday. Null = not planned.
  IntColumn get daysMask => integer().nullable()();
  BoolColumn get heatExposure => boolean().withDefault(const Constant(false))();
  TextColumn get status => text()
      .withDefault(const Constant('activo'))
      .check(status.isIn(const ['activo', 'pausado', 'archivado']))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text()();
}
