// Drift column checks reference their own getter by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

/// What earns leisure tokens (B7): the user's choice of habits and events.
@DataClassName('TokenEarnRuleRow')
class TokenEarnRules extends Table {
  /// `habit:<id>`, `entreno`, `comida` or `cierre`.
  TextColumn get source => text()();
  IntColumn get tokens => integer().check(tokens.isBiggerThanValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {source};
}

/// What a kind of leisure costs: tokens for each started block of minutes.
@DataClassName('TokenCostRuleRow')
class TokenCostRules extends Table {
  /// An app category code (B2).
  TextColumn get category => text()();
  IntColumn get tokens => integer().check(tokens.isBiggerThanValue(0))();
  IntColumn get perMinutes => integer().check(perMinutes.isBiggerThanValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {category};
}

/// The ledger, one row per day and source (`gasto:<category>` for what was
/// spent). Written only while tokens are on; never deleted when they are
/// turned off.
@DataClassName('TokenDayRow')
class TokenDays extends Table {
  TextColumn get date => text()();
  TextColumn get source => text()();
  IntColumn get earned => integer().withDefault(const Constant(0)).check(earned.isBiggerOrEqualValue(0))();
  IntColumn get spent => integer().withDefault(const Constant(0)).check(spent.isBiggerOrEqualValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {date, source};
}
