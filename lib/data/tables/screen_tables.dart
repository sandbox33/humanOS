// Drift column checks reference their own getter by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

/// The user's category for each app (B2). Apps without a row are shown
/// with a suggestion until the user decides.
@DataClassName('AppClassRow')
class AppClasses extends Table {
  TextColumn get package => text()();
  TextColumn get category => text().check(
        category.isIn(const ['trabajo', 'comunicacion', 'ocio', 'redes', 'utilidades', 'sin_clasificar']),
      )();
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {package};
}

/// Minutes each app was on screen per calendar day, kept on the phone in
/// the encrypted database (the system keeps its events only some days).
@DataClassName('AppUsageDayRow')
class AppUsageDays extends Table {
  /// `YYYY-MM-DD`.
  TextColumn get date => text()();
  TextColumn get package => text()();
  IntColumn get minutes => integer().check(minutes.isBiggerOrEqualValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {date, package};
}
