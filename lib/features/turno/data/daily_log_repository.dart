import 'package:drift/drift.dart';

import '../../../data/user_db.dart';

/// `daily_logs`: shift effort, heat, fluids, sweat test, screen time,
/// sobriety, subjective sleep and the "día completo" confirmation.
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

  /// Latest valid sweat-test rate (L/h), searching backwards.
  Future<({double rate, String date})?> latestSweatRate() async {
    final rows = await (_db.select(_db.dailyLogs)
          ..where((t) =>
              t.sweatPreKg.isNotNull() & t.sweatPostKg.isNotNull() & t.heatHours.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.date)])
          ..limit(10))
        .get();
    for (final r in rows) {
      final hours = r.heatHours ?? 0;
      if (hours <= 0) continue;
      final rate = (r.sweatPreKg! - r.sweatPostKg! + (r.fluidsL ?? 0) - (r.urineL ?? 0)) / hours;
      if (rate > 0) return (rate: rate, date: r.date);
    }
    return null;
  }
}
