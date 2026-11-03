import 'package:drift/drift.dart';

import '../../../data/user_db.dart';

/// `daily_logs`: effort, heat minutes, sweat feel, thermos, mood, screen
/// time, sobriety, subjective sleep and the "día completo" confirmation.
class DailyLogRepository {
  DailyLogRepository(this._db);
  final UserDb _db;

  Stream<DailyLogRow?> watchDay(String date) =>
      (_db.select(_db.dailyLogs)..where((t) => t.date.equals(date))).watchSingleOrNull();

  Stream<List<DailyLogRow>> watchSince(String from) => (_db.select(_db.dailyLogs)
        ..where((t) => t.date.isBiggerOrEqualValue(from))
        ..orderBy([(t) => OrderingTerm.asc(t.date)]))
      .watch();

  Future<List<DailyLogRow>> since(String from) => (_db.select(_db.dailyLogs)
        ..where((t) => t.date.isBiggerOrEqualValue(from))
        ..orderBy([(t) => OrderingTerm.asc(t.date)]))
      .get();

  Future<DailyLogRow?> day(String date) =>
      (_db.select(_db.dailyLogs)..where((t) => t.date.equals(date))).getSingleOrNull();

  /// Writes only the given fields (absent values keep what is stored).
  Future<void> update(String date, DailyLogsCompanion fields) async {
    await _db.transaction(() async {
      final exists = await day(date) != null;
      if (!exists) {
        await _db.into(_db.dailyLogs).insert(DailyLogsCompanion.insert(date: date));
      }
      await (_db.update(_db.dailyLogs)..where((t) => t.date.equals(date))).write(fields);
    });
  }
}
