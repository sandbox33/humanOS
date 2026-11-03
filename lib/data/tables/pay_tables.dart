// Drift column checks reference their own getter by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

/// What the user was paid, with the normal and overtime minutes it covers
/// (B5). Cents and minutes only; no rate is assumed.
@DataClassName('PayWeekRow')
class PayWeeks extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `YYYY-MM-DD`, the day the money came in.
  TextColumn get paidOn => text()();
  IntColumn get amountCents => integer().check(amountCents.isBiggerThanValue(0))();
  IntColumn get normalMinutes => integer().check(normalMinutes.isBiggerOrEqualValue(0))();
  IntColumn get overtimeMinutes => integer().check(overtimeMinutes.isBiggerOrEqualValue(0))();

  /// The overtime part of the amount, when the pay slip shows it.
  IntColumn get overtimeCents => integer().nullable().check(overtimeCents.isBiggerOrEqualValue(0))();
  TextColumn get note => text().nullable()();
  TextColumn get createdAt => text()();
}

/// The cash the user counted at a moment (B5). The app keeps it up to date
/// with the expenses and pay logged after it.
@DataClassName('CashCountRow')
class CashCounts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Local wall-clock `YYYY-MM-DDTHH:MM:SS`.
  TextColumn get countedAt => text()();
  IntColumn get cents => integer()();
}
