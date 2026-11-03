// Drift column checks reference their own getter by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

/// The day's close (B6): mood, energy and the answer to the user's own
/// question. Stays on the phone, encrypted; never in logs.
@DataClassName('DayCloseRow')
class DayCloses extends Table {
  /// `YYYY-MM-DD`.
  TextColumn get date => text()();
  IntColumn get mood => integer().check(mood.isBetweenValues(1, 5))();
  IntColumn get energy => integer().check(energy.isBetweenValues(1, 5))();

  /// Null when the question was not answered.
  BoolColumn get honestyYes => boolean().nullable()();
  TextColumn get honestyNote => text().nullable()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

/// The user's categories of time with people. Nothing is preloaded.
@DataClassName('InteractionCategoryRow')
class InteractionCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text().unique()();
  TextColumn get status =>
      text().withDefault(const Constant('activo')).check(status.isIn(const ['activo', 'archivado']))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text()();
}

/// Minutes with people per category on a closed day.
@DataClassName('DayCloseInteractionRow')
class DayCloseInteractions extends Table {
  TextColumn get date => text()();
  IntColumn get categoryId => integer().references(InteractionCategories, #id)();
  IntColumn get minutes => integer().check(minutes.isBiggerOrEqualValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {date, categoryId};
}
