// Drift column checks reference their own getter by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

/// One expense. Money in integer cents; the category is the user's label
/// at the time (kept even if the category is later archived).
@DataClassName('ExpenseRow')
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `YYYY-MM-DD`.
  TextColumn get date => text()();
  TextColumn get category => text()();
  IntColumn get amountCents => integer().check(amountCents.isBiggerThanValue(0))();
  BoolColumn get planned => boolean().withDefault(const Constant(false))();
  BoolColumn get impulse => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  TextColumn get createdAt => text()();
}

/// Expense categories created by the user. Nothing is preloaded.
@DataClassName('ExpenseCategoryRow')
class ExpenseCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text().unique()();
  TextColumn get status =>
      text().withDefault(const Constant('activo')).check(status.isIn(const ['activo', 'archivado']))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text()();
}

/// User goals; a goal with a parent is a sub-goal and the parent's
/// progress comes from its sub-goals. No goal is preloaded.
@DataClassName('GoalRow')
class Goals extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get parentId => integer().nullable().references(Goals, #id)();
  TextColumn get title => text()();

  /// Unknown cost stays NULL (no ETA).
  IntColumn get targetCents => integer().nullable().check(targetCents.isBiggerOrEqualValue(0))();
  IntColumn get savedCents => integer().withDefault(const Constant(0)).check(savedCents.isBiggerOrEqualValue(0))();

  /// Lower first (the user's order).
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get status => text()
      .withDefault(const Constant('activo'))
      .check(status.isIn(const ['activo', 'pausado', 'completado', 'descartado']))();
  TextColumn get createdAt => text()();
  TextColumn get completedAt => text().nullable()();

  /// Real cost recorded on completion, next to the estimate.
  IntColumn get actualCents => integer().nullable().check(actualCents.isBiggerOrEqualValue(0))();
}

/// An unplanned purchase waiting out its pause before the user decides.
@DataClassName('PurchasePauseRow')
class PurchasePauses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get category => text()();
  IntColumn get amountCents => integer().check(amountCents.isBiggerThanValue(0))();
  TextColumn get note => text().nullable()();
  TextColumn get createdAt => text()();

  /// Local wall-clock `YYYY-MM-DDTHH:MM:SS` when the pause ends.
  TextColumn get untilTs => text()();
  TextColumn get status => text()
      .withDefault(const Constant('esperando'))
      .check(status.isIn(const ['esperando', 'comprado', 'descartado']))();
}
