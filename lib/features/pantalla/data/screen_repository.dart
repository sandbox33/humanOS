import 'package:drift/drift.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../data/user_db.dart';
import '../../trabajo/data/work_repository.dart' show stampOf;

/// App classes and daily minutes per app. Everything stays in the
/// encrypted database; nothing is sent anywhere.
class ScreenRepository {
  ScreenRepository(this._db, this._now);
  final UserDb _db;
  final DateTime Function() _now;

  Stream<Map<String, AppCategory>> watchClasses() => _db
      .select(_db.appClasses)
      .watch()
      .map((rows) => {for (final r in rows) r.package: AppCategory.parse(r.category)});

  Future<void> setClass(String package, AppCategory category) => _db.into(_db.appClasses).insertOnConflictUpdate(
        AppClassesCompanion.insert(package: package, category: category.code, updatedAt: stampOf(_now())),
      );

  /// Replaces the minutes of [date] with [byApp] (a day is recomputed
  /// whole from the phone's events).
  Future<void> replaceDay(String date, Map<String, int> byApp) => _db.transaction(() async {
        await (_db.delete(_db.appUsageDays)..where((t) => t.date.equals(date))).go();
        await _db.batch((b) {
          b.insertAll(_db.appUsageDays, [
            for (final e in byApp.entries) AppUsageDaysCompanion.insert(date: date, package: e.key, minutes: e.value),
          ]);
        });
      });

  Stream<List<AppUsageDayRow>> watchDaysSince(String from) =>
      (_db.select(_db.appUsageDays)..where((t) => t.date.isBiggerOrEqualValue(from))).watch();
}
